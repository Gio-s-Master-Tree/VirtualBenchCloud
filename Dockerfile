# ================================
# Build stage
# ================================
FROM swift:6.0 AS builder

WORKDIR /build

# Copy Package manifests first for dependency caching
COPY Package.swift Package.resolved* ./
RUN swift package resolve

# Copy source and build
COPY Sources/ Sources/
COPY Tests/ Tests/

RUN swift build -c release \
    --static-swift-stdlib \
    -Xlinker -lstdc++

# ================================
# Runtime stage
# ================================
FROM swift:6.0-slim

WORKDIR /app

# Copy the built executable
COPY --from=builder /build/.build/release/Run /app/Run

# Create a non-root user
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor
USER vapor

EXPOSE 8080

ENTRYPOINT ["/app/Run"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
