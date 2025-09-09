require 'bundler'
Bundler.require(:default)

loader = Zeitwerk::Loader.new
loader.push_dir('models')
loader.setup

BASE_URL = ENV.fetch('BASE_URL', 'http://localhost:9292').freeze
KICAD_SCHEMA_URL = ENV.fetch('KICAD_SCHEMA_URL', 'https://go.kicad.org/pcm/schemas/v1').freeze
REDIRECT_URL = ENV.fetch('REDIRECT_URL', 'http://example.com').freeze
MAINTAINER_URL = ENV.fetch('MAINTAINER_URL', 'http://example.com').freeze
MAINTAINER_NAME = ENV.fetch('MAINTAINER_NAME', 'Private KiCad Repository')
REPOSITORY_NAME = ENV.fetch('REPOSITORY_NAME', 'Private KiCad Repository')
PLAUSIBLE_ENABLED = (ENV.fetch('PLAUSIBLE_ENABLED', 'true') == 'false').freeze
PLAUSIBLE_DOMAIN = ENV.fetch('PLAUSIBLE_DOMAIN', false).freeze

# Database configuration
DB = Sequel.connect(ENV.fetch('DATABASE_URL', 'sqlite://db/data/sqlite.db'))

# Load migrations
Sequel.extension :migration
Sequel::Migrator.run(DB, 'db/migrations')

class KiCadPkgServer < Sinatra::Base
  configure do
    set :show_exceptions, false
    set :raise_errors, false
    set :host_authorization, { permitted_hosts: [] }
  end
  
  error do
    content_type :json
    status 500
    {
      error: env['sinatra.error'].message
    }.to_json
  end

  after do
    track_request(request)
  end
  
  # Push endpoint
  post '/api/push' do
    content_type :json

    # Parse request body
    request_data = JSON.parse(request.body.read)
    git_url = request_data['url']
    
    unless git_url
      status 400
      return { error: 'Git URL is required' }.to_json
    end
    
    # Create temporary directory for cloning
    temp_dir = Dir.mktmpdir
    
    begin
      # Clone repository
      repo = Rugged::Repository.clone_at(git_url, temp_dir)

      if request_data.has_key?('tag')
        tag_ref = repo.references["refs/tags/#{request_data['tag']}"]
        if tag_ref
          target_commit = repo.lookup(tag_ref.target_id)
          repo.checkout(target_commit.oid, strategy: :force)
          repo.head = tag_ref.name
        else
          puts "Tag #{request_data['tag']} not found"
        end
      end
      
      # Read & validate meta.json
      meta_path = File.join(temp_dir, 'metadata.json')
      unless File.exist?(meta_path)
        status 400
        return { error: 'metadata.json not found in repository' }.to_json
      end

      meta_data = JSON.load(File.read(meta_path))
      validation = JSON::Validator.fully_validate(fetch_kicad_schema, meta_data)
      unless validation.empty?
        status 400
        return { error: 'metadata.json not valid according to pcm.v1.schema.json', details: validation }.to_json
      end
      
      # Create ZIP file from src directory
      zip_buffer, install_size = create_zip_from_repository(temp_dir)
      
      # Calculate SHA256 and size
      sha256 = Digest::SHA256.hexdigest(zip_buffer.read)
      size = zip_buffer.size
      zip_buffer.rewind
      
      # Create or update package in database
      package = Package.find(url: git_url)
      
      package_data = {
        url: git_url,
        zip_data: Sequel.blob(zip_buffer.read),
        icon_data: Sequel.blob(IO.read(File.join(temp_dir, 'resources', 'icon.png'))),
        sha256: sha256,
        size: size,
        install_size: install_size,
        name: meta_data['name'],
        identifier: meta_data['identifier'],
        metadata_json: JSON.dump(meta_data),
      }
      
      if package
        package.update(package_data)
      else
        package = Package.create(package_data)
      end
      
      status 201
      {
        message: 'Package created successfully',
        sha256: sha256,
        size: size
      }.to_json
      
    ensure
      # Clean up temporary directory
      FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end
  end

  get '/' do
    if request.user_agent.include? 'KiCad'
      @latest_update = Package.order(:updated_at).first&.updated_at || Time.now
      @packages_sha256 = Digest::SHA256.hexdigest(Package.all_as_json)
      @resources_sha256 = Digest::SHA256.hexdigest(Package.resources_zip.read)

      content_type 'application/json'
      erb :repository
    else
      redirect REDIRECT_URL
    end
  end
  
  # Packages endpoint
  get '/packages.json' do
    content_type 'application/json'

    Package.all_as_json
  end

  get '/resources.zip' do
    content_type 'application/zip'
    attachment "resources.zip"

    Package.resources_zip
  end

  get '/packages/:id/download.zip' do
    package = Package[params[:id]]
    
    unless package
      status 404
      return { error: 'Package not found' }.to_json
    end
    
    content_type 'application/zip'
    attachment "package_#{package.id}.zip"

    package.zip_data
  end
  
  private
  
  def create_zip_from_repository(directory_path)
    size = 0
    io = Zip::OutputStream.write_buffer do |zos|
      directory = nil
      source_dir = nil
      Dir.glob(File.join(directory_path, '**', '*'), File::FNM_DOTMATCH).each do |f|
        filename = File.basename(f)
        if filename == '.kicad_pcm'
          directory = File.read(f)
          source_dir = File.dirname(f)
        elsif filename == 'icon.png'
          zos.put_next_entry('resources/icon.png')
          zos.write(File.read(f))
          size += File.size(f)
        elsif filename == 'metadata.json'
          zos.put_next_entry('metadata.json')
          zos.write(File.read(f))
          size += File.size(f)
        elsif directory && source_dir == File.dirname(f)
          zos.put_next_entry(File.join(directory, filename))
          zos.write(File.read(f))
          size += File.size(f)
        end
      end
    end
    io.rewind

    [io, size]
  end

  def fetch_kicad_schema
    url_to_schema = Excon.get(KICAD_SCHEMA_URL)
    rsp = Excon.get(url_to_schema.headers['location'])

    # JSON Schema validator does not yet support draft-07 thus replace with draft-06
    JSON.load(rsp.body.sub(/draft-07/, 'draft-06'))
  end

  def track_request(request)
    return unless PLAUSIBLE_ENABLED

    headers = {
      'User-Agent' => request.user_agent,
      'Content-Type' => 'application/json',
      'X-Forwarded-For' => request.ip
    }
    payload = {
      name: 'pageview',
      url: request.url,
      domain: PLAUSIBLE_DOMAIN
    }

    Excon.post('https://plausible.io/api/event', body: JSON.dump(payload), headers: headers)
  rescue Excon::Error => e
  end
end

