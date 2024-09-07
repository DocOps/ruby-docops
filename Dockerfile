ARG BASE_IMAGE=ruby
ARG RUBY_VERSION=2.7
ARG DISTRO=slim-bullseye

FROM $BASE_IMAGE:$RUBY_VERSION-$DISTRO

# This Dockerfile builds three distinct images with some variation possible for each.
# The "work" IMAGE_CONTEXT is for a development environment (default).
# The "live" IMAGE_CONTEXT is for a staging, testing, or production environment.
# Adding NodeJS and/or Python is optional in both contexts.
# Zshell is installed only in the "work" context.
# Git is installed and can perform clone operations on public repos.
# Only in work environments where the user consents will Git be configured with a name, email, and SSH key.
# For "live" images, SSH keys should be mounted as a secret volume and/or handled in post-build script.

# Set remaining build arguments
ARG DOCKERFILE_DIR="."
ARG BUILD_SCRIPT_PRE="dockerfile-pre-build.sh"
ARG BUILD_SCRIPT_POST="dockerfile-post-build.sh"
ARG PRE_BUILD_SCRIPT_ARGS=""
ARG POST_BUILD_SCRIPT_ARGS=""
ARG IMAGE_CONTEXT="work"
ARG UID=1000
ARG GID=1000
ARG GIT_NAME
ARG GIT_EMAIL
ARG ADD_NODEJS=true
ARG ADD_PYTHON=true
ARG ADD_PANDOC=true
ARG ADD_REDOCLY=true
ARG RUN_USER="appuser"
ARG NODEJS_VERSION="20"
ARG PYTHON_VERSION="3.12.3"
ADD REDOCLY_VERSION="latest"
ARG WORKDIR="/usr/src/app"

LABEL version="0.1.0" \
    IMAGE_CONTEXT=$IMAGE_CONTEXT \
    NODEJS=$ADD_NODEJS \
    PYTHON=$ADD_PYTHON \
    REDOCLY=$ADD_REDOCLY \
    PANDOC=$ADD_PANDOC \
    RUBY_VERSION=$RUBY_VERSION \
    NODEJS_VERSION=$NODEJS_VERSION \
    PYTHON_VERSION=$PYTHON_VERSION \
    WORKDIR=$WORKDIR \
    RUN_USER=$RUN_USER

ENV BUNDLE_PATH=/$WORKDIR/.bundle \
    GEM_HOME=/$WORKDIR/.bundle \
    GEM_PATH=/$WORKDIR/.bundle \
    BUNDLE_BIN=/$WORKDIR/.bundle/bin

# HOOK for custom operations
COPY $DOCKERFILE_DIR/$BUILD_SCRIPT_PRE $WORKDIR/build-script-pre.sh
RUN if [[ -f $WORKDIR/build-script-pre.sh ]]; then \
      chmod +x $WORKDIR/build-script-pre.sh \
      && $WORKDIR/build-script-pre.sh $PRE_BUILD_SCRIPT_ARGS \
  ; fi

# Install core packages
RUN apt-get update && apt-get install -y --no-install-recommends \
  apt-utils \
  curl \
  openssh-client \
  build-essential \
  findutils \
  git \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install additional packages/tools for the "work" image
RUN if [ "$IMAGE_CONTEXT" = "work" ] ; then \
      apt-get update && apt-get install -y --no-install-recommends \
      gnupg \
      zsh \
      nano \
      wget \
      sudo \
      inotify-tools \
      tzdata \
      fonts-dejavu \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/* \
    else \
      echo "Extra utilities skipped" \
  ; fi

# Conditionally install Pandoc
RUN if [ "$ADD_PANDOC" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
      pandoc \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/* \
    else \
      echo "Pandoc skipped" \
  ; fi

# Conditionally install Node.js
RUN if [ "$ADD_NODEJS" = "true" ]; then \
      curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
      && apt-get update && apt-get install -y nodejs \
      && npm install -g yarn \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/* \
    else \
      echo "Node.js skipped" \
  ; fi

RUN mkdir -p $WORKDIR/.bundle && \
    echo 'BUNDLE_PATH: .bundle' > $WORKDIR/.bundle/config

# Create a new group and user with the provided UID and GID
RUN groupadd -g $GID appgroup && \
    useradd -u $UID -g appgroup -m -d /home/$RUN_USER -s /bin/bash $RUN_USER

RUN if [ "$IMAGE_CONTEXT" = "work" ]; then \
      chsh -s /bin/zsh $RUN_USER \
      && echo "$RUN_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$RUN_USER \
      && chmod 0440 /etc/sudoers.d/$RUN_USER \
  ; fi

# Conditionally install Python
RUN if [ "$ADD_PYTHON" = "true" ]; then \
      apt-get update && apt-get install -y python3 python3-pip \
      && apt-get clean \
      && rm -rf /var/lib/apt/lists/* \
    else \
      echo "Python skipped" \
  ; fi

# Set the user
USER $RUN_USER

# Optionally install redocly
RUN if [ "$ADD_REDOCLY" = "true" && "$ADD_NODEJS" = "true" ]; then \
      npm install -g @redocly/openapi-cli \
    else \
      echo "Redocly skipped" \
  ; fi

# Configure Git
RUN if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then \
        git config --global user.name "$GIT_NAME" && \
        git config --global user.email "$GIT_EMAIL" \
        mkdir -p /home/$RUN_USER/.ssh && \
        chmod 700 /home/$RUN_USER/.ssh && \
        chown -R $RUN_USER:$RUN_USER /home/$RUN_USER/.ssh \
    else \
        git config --global --add safe.directory $WORKDIR \
  ; fi

# Install Oh My Zsh
RUN if [ "$IMAGE_CONTEXT" = "work" ]; then \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
      && echo 'autoload -Uz compinit; compinit' >> /home/$RUN_USER/.zshrc \
      && sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions)/' /home/$RUN_USER/.zshrc \
  ; fi

RUN echo 'alias jekyllserve="jekyll serve --host=0.0.0.0"' >> /home/$RUN_USER/.zshrc

# HOOK for custom operations
COPY $DOCKERFILE_DIR/$BUILD_SCRIPT_POST $WORKDIR/build-script-post.sh
RUN if [[ -f $WORKDIR/build-script-post.sh ]]; then \
      chmod +x $WORKDIR/build-script-post.sh \
      && $WORKDIR/build-script-post.sh $POST_BUILD_SCRIPT_ARGS \
  ; fi

WORKDIR $WORKDIR

CMD [ "bash" ]