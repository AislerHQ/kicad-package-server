Sequel.migration do
  up do
    create_table(:packages) do
      primary_key :id
      String :url, null: false
      String :identifier, null: false
      String :name, null: false
      File :zip_data, null: false  # Binary data for ZIP
      File :icon_data
      String :sha256, null: false
      Integer :size, null: false
      Integer :install_size

      Text :metadata_json, null: false
      
      DateTime :created_at, null: false
      DateTime :updated_at, null: false
      
      index :url
      index :identifier
    end
  end
  
  down do
    drop_table(:packages)
  end
end
