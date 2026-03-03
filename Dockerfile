# Mesher - Mesh application container
#
# NOTE: This Dockerfile assumes meshc is available in the build image.
# The exact base image depends on how Mesh binaries are distributed.
# Adjust the FROM line to point to the correct Mesh SDK image or
# install meshc from the appropriate source.

# Stage 1: Build
FROM ubuntu:24.04 AS build

# Install meshc (placeholder — replace with actual Mesh SDK installation)
# COPY --from=mesh-sdk /usr/local/bin/meshc /usr/local/bin/meshc
# For now, assume meshc is installed in the build environment.

WORKDIR /app

COPY mesh.toml .
COPY src/ src/
COPY migrations/ migrations/

# Compile the Mesh application
# RUN meshc build .

# Stage 2: Runtime
FROM ubuntu:24.04

WORKDIR /app

# Copy compiled binary from build stage
# COPY --from=build /app/build/mesher .

# Copy frontend assets if they exist
# COPY --from=build /app/frontend/dist ./frontend/dist

# Copy source and config for development (until meshc build is functional)
COPY --from=build /app/ .

EXPOSE 8080

# Run the compiled binary (adjust path once meshc build output is known)
# CMD ["./mesher"]
CMD ["echo", "Replace with meshc run or compiled binary once Mesh SDK is available"]
