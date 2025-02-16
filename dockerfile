FROM ubuntu:latest

# Install required packages
RUN apt-get update && apt-get install -y \
    npm \
    lua5.1 \
    luarocks \
    build-essential \
    wget \
    gawk

# Install luamin globally via npm
RUN npm install -g luamin

# Install Lua dependencies
RUN luarocks install luacc

# Set working directory
WORKDIR /app

# Make build script executable
COPY build.sh /app/
RUN chmod +x /app/build.sh

# add github to known hosts
#RUN ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

RUN git fetch --unshallow || true

# Command to run when container starts
CMD ["./build.sh"]