FROM docker.io/sepen/crux-multiarch

# Create non-root build user
RUN \
  useradd -m builder && \
  echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER builder
WORKDIR /home/builder

COPY Makefile /home/builder/Makefile

# Build toolchain
RUN make toolchain

# Default command
CMD ["/bin/bash"]

