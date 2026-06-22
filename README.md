# Container Desktop

A native SwiftUI interface for [Apple container](https://github.com/apple/container). Container Desktop provides familiar container, image, build, log, and resource-management workflows while keeping the underlying CLI commands visible.

## Features

- Start and stop the Apple container service
- Run, inspect, stop, restart, kill, and delete containers
- View logs and resource statistics
- Open interactive container shells in Terminal
- Pull, tag, push, and delete OCI images
- Build Dockerfiles with live output and cancellation
- Configure ports, environment variables, mounts, CPU, and memory
- Save reusable run configurations
- Export sanitized diagnostics

Compose projects, automatic CLI installation, registry credential UI, and embedded terminal emulation are not currently supported.

## Requirements

- Apple silicon Mac
- macOS 26 or newer
- Apple `container` installed from its [signed release package](https://github.com/apple/container/releases/latest)
- Swift 6.2 or newer when building Container Desktop from source

Apple container produces and consumes standard OCI images, including compatible images published on Docker Hub and GHCR.

## Quick start

Install Apple container, then confirm it is available:

```sh
container system version
container system start
```

Build the macOS application:

```sh
./scripts/build-app.sh
open "dist/Container Desktop.app"
```

The finished application is located at `dist/Container Desktop.app`.

For development, run directly through Swift Package Manager:

```sh
swift run ContainerDesktop
```

## Using the app

### Dashboard

The Dashboard shows service health, running and stopped container counts, image count, and recent operations. Start the Apple container service here when it is stopped.

### Containers

Select **Run** and configure:

- **Image:** OCI reference such as `docker.io/library/nginx:alpine`
- **Name:** friendly container identifier
- **Command:** optional process and arguments
- **Environment:** one `KEY=value` entry per line
- **Ports:** one `host-port:container-port` entry per line
- **Mounts:** one Apple container mount specification per line
- **CPU / Memory:** optional limits such as `2` and `1G`
- **Auto-remove:** delete the container after it stops

The form shows the exact generated CLI command. Select an existing container to view details, logs, inspect output, statistics, and lifecycle actions.

### Images

Pull images with a fully qualified reference when possible:

```text
docker.io/library/alpine:latest
docker.io/library/nginx:alpine
ghcr.io/owner/application:v1
```

Pulling an image does not create a container. Select the downloaded image and choose **Run** to create one.

Registry authentication is performed in Terminal so Container Desktop never collects passwords:

```sh
container registry login REGISTRY
```

### Builds

Choose a build-context directory, optionally select a Dockerfile, enter an image tag, and choose **Build Image**. The context contains every local file available to Dockerfile `COPY` and `ADD` instructions.

### Settings

Settings control the CLI path, refresh interval, default shell, operation-history retention, service state, and diagnostics export.

## Guides

### Run an existing Docker image

This example runs the official nginx Alpine image at [http://localhost:8080](http://localhost:8080).

In Container Desktop:

1. Open **Images** and pull `docker.io/library/nginx:alpine`.
2. Wait for the pull operation to finish.
3. Select the image and choose **Run**.
4. Set the name to `example-nginx`.
5. Add `8080:80` under Ports.
6. Choose **Run**.

CLI equivalent:

```sh
container image pull docker.io/library/nginx:alpine
container run \
  --name example-nginx \
  --detach \
  --publish 8080:80 \
  docker.io/library/nginx:alpine

open http://localhost:8080
```

Clean up:

```sh
container stop example-nginx
container delete example-nginx
container image delete docker.io/library/nginx:alpine
```

### Build a web server

The repository includes a working example under `Example/hello-web`:

```text
Example/hello-web/
├── Dockerfile
└── index.html
```

Build it in the app by selecting `Example/hello-web` as the context and `hello-web:latest` as the tag. Run the resulting image with port `8080:8000`.

CLI equivalent:

```sh
container build --tag hello-web:latest Example/hello-web
container run \
  --name hello-web \
  --detach \
  --publish 8080:8000 \
  hello-web:latest

open http://localhost:8080
```

Inspect the application:

```sh
container logs hello-web
container stats --no-stream hello-web
container exec --interactive --tty hello-web sh
```

### Build an existing Dockerfile project

Most standard Dockerfiles work directly with Apple container:

```text
my-application/
├── Dockerfile
├── .dockerignore
└── src/
```

Choose `my-application` as the build context and enter `my-application:local` as the tag. Files referenced by `COPY` must be inside the selected context.

```sh
container build --tag my-application:local my-application
container run \
  --name my-application \
  --detach \
  --publish 3000:3000 \
  --env NODE_ENV=production \
  my-application:local
```

Adjust ports and environment values for the application. Prefer base images that provide a `linux/arm64` variant.

### Mount an existing website

Run nginx with a read-only host directory:

```sh
container run \
  --name mounted-site \
  --detach \
  --publish 8080:80 \
  --mount type=bind,source=/absolute/path/to/site,target=/usr/share/nginx/html,readonly \
  docker.io/library/nginx:alpine
```

In the app, enter the same value under Mounts and `8080:80` under Ports.

### Publish an image

```sh
container registry login ghcr.io
container image tag hello-web:latest ghcr.io/OWNER/hello-web:v1
container image push ghcr.io/OWNER/hello-web:v1
```

The destination repository must exist and the registry token must permit package publication.

## CLI reference

| Task | Command |
| --- | --- |
| Check version | `container system version` |
| Start service | `container system start` |
| Stop service | `container system stop` |
| List containers | `container list --all` |
| Start container | `container start NAME` |
| Stop container | `container stop NAME` |
| Delete container | `container delete NAME` |
| Follow logs | `container logs --follow NAME` |
| Open shell | `container exec --interactive --tty NAME sh` |
| View resources | `container stats NAME` |
| List images | `container image list` |
| Pull image | `container image pull IMAGE` |
| Build image | `container build --tag NAME .` |

## Development

### Project structure

```text
Sources/ContainerDesktop/   App, CLI client, models, state, and SwiftUI views
Tests/ContainerDesktopTests Dependency-free core unit tests
Example/hello-web/          Example Dockerfile project
Assets/                     Application icon sources
Packaging/                  Info.plist and signing entitlements
scripts/                    Test and application-build scripts
```

### Build

```sh
swift build
```

### Test

```sh
./scripts/test.sh
```

The suite covers run arguments, command quoting, redaction, current and legacy JSON formats, registry references, stats, status detection, errors, logs, process execution, and timeouts.

### Build the `.app`

```sh
./scripts/build-app.sh
```

The script performs a release build, generates `AppIcon.icns`, writes bundle metadata, applies a signature, verifies it, and creates:

```text
dist/Container Desktop.app
```

The default ad-hoc signature is suitable for local builds. For Developer ID signing:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APP_VERSION="0.1.0" \
BUILD_NUMBER="1" \
BUNDLE_IDENTIFIER="com.example.containerdesktop" \
./scripts/build-app.sh
```

Developer ID builds must be notarized before public distribution. Container Desktop is intentionally not sandboxed because it executes the installed CLI and accesses user-selected build contexts.

## Troubleshooting

### Apple container is not detected

Install Apple's signed package or set its executable path under Settings. The common path is `/usr/local/bin/container`.

### Service is stopped

Start it from the Dashboard or run `container system start`.

### A port is already in use

Choose another host port. For example, replace `8080:80` with `8081:80`.

### Registry authentication fails

Run `container registry login REGISTRY` in Terminal. Credentials are managed by Apple container and omitted from Container Desktop diagnostics.

### A build cannot find a file

Confirm that the file is inside the build context and is not excluded by `.dockerignore`.

### An image only supports Intel Linux

Prefer a `linux/arm64` image. Apple container can use Rosetta for some `linux/amd64` workloads, but the current run form does not expose `--rosetta`.
