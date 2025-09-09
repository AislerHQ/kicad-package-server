# KiCad Package Server
This application provides a dead simple server for the KiCad Plugin and Content Manager (PCM). It allows to self-host
a centralized repository of plugins, libraries and color themes. It is independent of the official KiCad repository
provided by the KiCad Services Corporation.


## Getting started
The KiCad Package Server is best served using the Docker based deployment. To run the server execute
```bash
docker compose up
```
or check the docker-compose.yml file first for details about the deployment. By default, a SQLite3 database will be used,
Postgresql is also supported.  

The application expects Git repositories accessible via HTTPS. The root directory *must* contain a file named `metadata.json`,
it has to comply with the KiCad Package schema described at https://go.kicad.org/pcm/schemas/v1. This schema is validated and
any issues will be provided in the response.
Each directory which should be included in the final plugin *must* contain a file `.kicad_pcm` with the destination directory
as content. For example, if the plugin's source is located at src/, the following file is required
```bash
echo 'plugins' > src/.kicad_pcm
```
This helps the application to include the correct sources in the package.
Optionally place a file called `icon.png` inside the `resources` directory.

### Publishing a package
To publish a package just send a POST request to the server containing the Git repository
```bash
curl -X POST http://localhost:9292/api/push \
  -H "Content-Type: application/json" \
  -d '{"url": "https://github.com/AislerHQ/lovely-library.git"}'
```
Additionally, a tag can be specified
```bash
curl -X POST http://localhost:9292/api/push \
  -H "Content-Type: application/json" \
  -d '{"url": "https://github.com/AislerHQ/lovely-library.git", "tag": "v0.0.1"}'
```

### Enable Plausible tracking
Plausible is a privacy-first web-analytics service hosted in the EU, check https://plausible.io for details. If you want
to have detailed analytics about the usage of the repository and its provided packages, just set the environment variables
`PLAUSIBLE_ENABLED` to "true" and `PLAUSIBLE_DOMAIN` to the respective domain.
__This is disabled by default.__

### Environment variables
The following settings can be adjusted

| Variable Name | Default Value              | Description                                                              |
|---------------|----------------------------|--------------------------------------------------------------------------|
| `BASE_URL` | `http://localhost:9292`    | The base URL for the application server                                  |
| `REDIRECT_URL` | `https://example.com`      | URL to redirect users to, if server is requested directly (not by KiCad) |
| `MAINTAINER_URL` | `http://example.com`       | URL associated with the repository maintainer                            |
| `MAINTAINER_NAME` | `Private KiCad Repository` | Display name of the repository maintainer                                |
| `REPOSITORY_NAME` | `Private KiCad Repository` | Display name of the KiCad repository                                     |
| `PLAUSIBLE_ENABLED` | `false`                    | Boolean flag to enable/disable Plausible analytics                       |
| `PLAUSIBLE_DOMAIN` | `false`                    | Domain configuration for Plausible analytics tracking                    |
These can be set on the docker-compose.yml file.

## License
KiCad Package Server is Copyright © 2025 by AISLER B.V. It is free software, and may be
redistributed under the terms specified in the license file.

## About AISLER

![AISLER logo](https://aisler.net/logos/AISLER_Logo_m.png)

KiCad Package Server is developed and funded by AISLER B.V.

Looking for quick and affordable manufacturing for your Electronic Project? Visit us at [AISLER](https://aisler.net)