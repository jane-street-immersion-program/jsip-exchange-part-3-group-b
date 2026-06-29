# CI base image for the JSIP exchange project.
#
# This image bakes in the OxCaml compiler (ocaml-variants.5.2.0+ox) and every
# opam dependency of the project, so CI never has to build the compiler or
# recompile dependencies on each run. It is built and pushed to GitHub
# Container Registry by .github/workflows/build-image.yml, and consumed by
# .github/workflows/ci.yml via the `container:` key.
#
# Rebuild the image (via that workflow) whenever the dependency set changes.

FROM ubuntu:24.04

# opam settings that make sense inside a container:
#  - OPAMROOT: keep the opam root at a predictable, root-owned location.
#  - OPAMROOTISOK / OPAMYES / OPAMCONFIRMLEVEL: this image is built as root and
#    non-interactively, so allow that without prompting.
#  - OPAMSWITCH: the switch we create below; makes `opam env` unambiguous.
ENV OPAMROOT=/opt/opam \
    OPAMROOTISOK=1 \
    OPAMYES=1 \
    OPAMCONFIRMLEVEL=unsafe-yes \
    OPAMSWITCH=5.2.0+ox

# System dependencies: a C toolchain for building the compiler and native
# stubs, plus common -dev libraries that opam packages depexts depend on
# (gmp -> zarith, ffi -> ctypes, etc.). opam will apt-get install any further
# depexts itself during `opam install`.
# autoconf/automake/which are required by the OxCaml compiler's conf-* depexts.
# We deliberately keep the apt package lists (no `rm`) so that opam's depext
# mechanism can apt-get install any further system packages the dependency
# tree needs during `opam install` below.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        curl \
        git \
        libffi-dev \
        libgmp-dev \
        libpcre3-dev \
        libssl-dev \
        m4 \
        pkg-config \
        rsync \
        unzip \
        which \
        zlib1g-dev

# Install a pinned opam binary (same version setup-ocaml used).
RUN curl -fsSL \
        https://github.com/ocaml/opam/releases/download/2.5.1/opam-2.5.1-x86_64-linux \
        -o /usr/local/bin/opam \
    && chmod +x /usr/local/bin/opam

# Create the OxCaml switch and install the project's dependencies, then drop
# opam's caches -- all in a single RUN. This is done together on purpose: opam's
# download cache (which includes multi-GB git clones of the opam repositories)
# must be removed in the SAME layer that creates it, otherwise it stays baked
# into an earlier layer and bloats the image past what a CI runner can extract
# ("no space left on device" while unpacking).
#
# opam init registers the default repository; the switch then layers the OxCaml
# repository over it (ox first = higher priority), mirroring the official OxCaml
# install. Sandboxing is disabled because bubblewrap does not work in an
# unprivileged container build. None of the cleaned caches are needed at CI
# runtime (we only build, test, and run -- never `opam install` again).
WORKDIR /src
COPY jsip-exchange.opam ./
RUN opam init --bare --disable-sandboxing \
    && opam switch create 5.2.0+ox ocaml-variants.5.2.0+ox \
        --repos ox=git+https://github.com/oxcaml/opam-repository.git,default \
    && opam install . --deps-only --with-test \
    && opam clean --download-cache --repo-cache --logs --yes

# Bake the switch environment into the image so `dune`/tools are on PATH even
# in non-login shells. CI steps additionally run `eval $(opam env)` for the
# full set of variables (CAML_LD_LIBRARY_PATH, etc.).
ENV PATH=/opt/opam/5.2.0+ox/bin:$PATH \
    OPAM_SWITCH_PREFIX=/opt/opam/5.2.0+ox
