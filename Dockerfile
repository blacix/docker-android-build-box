FROM ubuntu:20.04

# ANDROID_HOME is deprecated
ENV ANDROID_HOME="/opt/android-sdk" \
    ANDROID_SDK_HOME="/opt/android-sdk" \
    ANDROID_SDK_ROOT="/opt/android-sdk" \
    ANDROID_NDK="/opt/android-sdk/ndk/current" \
    ANDROID_NDK_ROOT="/opt/android-sdk/ndk/current" \
    FLUTTER_HOME="/opt/flutter"
ENV ANDROID_SDK_MANAGER=${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager

# support amd64 and arm64
RUN JDK_PLATFORM=$(if [ "$(uname -m)" = "aarch64" ]; then echo "arm64"; else echo "amd64"; fi) && \
    echo export JDK_PLATFORM=$JDK_PLATFORM >> /etc/jdk.env && \
    echo export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-$JDK_PLATFORM/" >> /etc/jdk.env && \
    echo . /etc/jdk.env >> /etc/bash.bashrc && \
    echo . /etc/jdk.env >> /etc/profile

ENV TZ=America/Los_Angeles

# Get the latest version from https://developer.android.com/studio/index.html
ENV ANDROID_SDK_TOOLS_VERSION="8512546"

# nodejs version
ENV NODE_VERSION="14.x"

ENV DEBIAN_FRONTEND="noninteractive" \
    TERM=dumb \
    DEBIAN_FRONTEND=noninteractive

ENV PATH="$JAVA_HOME/bin:$PATH:$ANDROID_SDK_HOME/emulator:$ANDROID_SDK_HOME/cmdline-tools/latest/bin:$ANDROID_SDK_HOME/tools:$ANDROID_SDK_HOME/platform-tools:$ANDROID_NDK:$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin"

WORKDIR /tmp
    
        
# Installing packages
RUN dpkg --add-architecture i386 && apt-get update -qq > /dev/null && \
    apt-get install -qq --no-install-recommends \
        libc6:i386 libncurses5:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386 \
        build-essential \
        cmake \
        openjdk-11-jdk \
        unzip \
        wget \
        # zipalign \
        && \
    echo "JVM directories: `ls -l /usr/lib/jvm/`" && \
    . /etc/jdk.env && \
    echo "Java version (default):" && \
    java -version && \
    echo "set timezone" && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt-get -y clean && apt-get -y autoremove && rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/* /var/tmp/*

# Install Android SDK
RUN echo "sdk tools ${ANDROID_SDK_TOOLS_VERSION}" && \
    wget --quiet --output-document=sdk-tools.zip \
        # "https://dl.google.com/android/repository/sdk-tools-linux-${ANDROID_SDK_TOOLS_VERSION}.zip" && \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS_VERSION}_latest.zip" && \
    mkdir --parents "$ANDROID_HOME" && \
    unzip -q sdk-tools.zip -d "$ANDROID_HOME" && \
    cd "$ANDROID_HOME" && \
    mv cmdline-tools latest && \
    mkdir cmdline-tools && \
    mv latest cmdline-tools && \
    rm --force sdk-tools.zip

# Install SDKs
# Please keep these in descending order!
# The `yes` is for accepting all non-standard tool licenses.
RUN mkdir --parents "$ANDROID_HOME/.android/" && \
    echo '### User Sources for Android SDK Manager' > \
        "$ANDROID_HOME/.android/repositories.cfg" && \
    . /etc/jdk.env && \
    yes | $ANDROID_SDK_MANAGER --licenses

# List all available packages.
# redirect to a temp file `packages.txt` for later use and avoid show progress
RUN . /etc/jdk.env && \
    $ANDROID_SDK_MANAGER --list > packages.txt && \
    cat packages.txt | grep -v '='


# https://developer.android.com/studio/command-line/sdkmanager.html
RUN echo "platforms" && \
    . /etc/jdk.env && \
    yes | $ANDROID_SDK_MANAGER \
        # "platforms;android-32" \
        "platforms;android-31" \
        > /dev/null

RUN echo "platform tools" && \
    . /etc/jdk.env && \
    yes | $ANDROID_SDK_MANAGER "platform-tools" > /dev/null

RUN echo "build tools 33.0.0" && \
    . /etc/jdk.env && \
    yes | $ANDROID_SDK_MANAGER \
        "build-tools;33.0.0" \
        # "build-tools;32.0.0" "build-tools;31.0.0" \
        # "build-tools;30.0.0" "build-tools;30.0.2" "build-tools;30.0.3" \
        # "build-tools;29.0.3" "build-tools;29.0.2" \
        # "build-tools;28.0.3" "build-tools;28.0.2" \
        # "build-tools;27.0.3" "build-tools;27.0.2" "build-tools;27.0.1" \
        # "build-tools;26.0.2" "build-tools;26.0.1" "build-tools;26.0.0" \
        > /dev/null

# seems there is no emulator on arm64
# Warning: Failed to find package emulator
# If emulator is not isntalled, as the licencse is accepted,gradle will try to install it on the first build.
# workaround: install it then remove it.
RUN echo "emulator" && \
    if [ "$(uname -m)" != "x86_64" ]; then echo "emulator only support Linux x86 64bit. skip for $(uname -m)"; exit 0; fi && \
    . /etc/jdk.env && \
    yes | $ANDROID_SDK_MANAGER "emulator" > /dev/null && \
    $ANDROID_SDK_MANAGER --uninstall emulator

RUN echo "bundletool" && \
    wget -q https://github.com/google/bundletool/releases/download/1.9.1/bundletool-all-1.9.1.jar -O bundletool.jar && \
    mv bundletool.jar $ANDROID_SDK_HOME/cmdline-tools/latest/

RUN echo "NDK" && \
    NDK=$(grep 'ndk;' packages.txt | sort | tail -n1 | awk '{print $1}') && \
    NDK_VERSION=$(echo $NDK | awk -F\; '{print $2}') && \
    echo "Installing $NDK" && \
    . /etc/jdk.env && \
    yes | $ANDROID_SDK_MANAGER "$NDK" > /dev/null && \
    ln -sv $ANDROID_HOME/ndk/${NDK_VERSION} ${ANDROID_NDK}


# RUN echo "Flutter sdk" && \
#     if [ "$(uname -m)" != "x86_64" ]; then echo "Flutter only support Linux x86 64bit. skip for $(uname -m)"; exit 0; fi && \
#     cd /opt && \
#     wget --quiet https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_2.10.3-stable.tar.xz -O flutter.tar.xz && \
#     tar xf flutter.tar.xz && \
#     git config --global --add safe.directory $FLUTTER_HOME && \
#     flutter config --no-analytics && \
#     rm -f flutter.tar.xz

# Copy sdk license agreement files.
RUN mkdir -p $ANDROID_HOME/licenses
COPY sdk/licenses/* $ANDROID_HOME/licenses/

# Create some jenkins required directory to allow this image run with Jenkins
RUN mkdir -p /var/lib/jenkins/workspace && \
    mkdir -p /home/jenkins && \
    chmod 777 /home/jenkins && \
    chmod 777 /var/lib/jenkins/workspace && \
    chmod -R 775 $ANDROID_HOME

# Add jenv to control which version of java to use, default to 11.
# RUN git clone https://github.com/jenv/jenv.git ~/.jenv && \
#     echo 'export PATH="$HOME/.jenv/bin:$PATH"' >> ~/.bash_profile && \
#     echo 'eval "$(jenv init -)"' >> ~/.bash_profile && \
#     . ~/.bash_profile && \
#     . /etc/jdk.env && \
#     java -version && \
#     # jenv add /usr/lib/jvm/java-8-openjdk-$JDK_PLATFORM && \
#     jenv add /usr/lib/jvm/java-11-openjdk-$JDK_PLATFORM && \
#     jenv versions && \
#     jenv global 11 && \
#     java -version

COPY README.md /README.md

ARG BUILD_DATE=""
ARG SOURCE_BRANCH=""
ARG SOURCE_COMMIT=""
ARG DOCKER_TAG=""

ENV BUILD_DATE=${BUILD_DATE} \
    SOURCE_BRANCH=${SOURCE_BRANCH} \
    SOURCE_COMMIT=${SOURCE_COMMIT} \
    DOCKER_TAG=${DOCKER_TAG}

WORKDIR /project

# labels, see http://label-schema.org/
LABEL maintainer="Ming Chen"
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.name="mingc/android-build-box"
LABEL org.label-schema.version="${DOCKER_TAG}"
LABEL org.label-schema.usage="/README.md"
LABEL org.label-schema.docker.cmd="docker run --rm -v `pwd`:/project mingc/android-build-box bash -c 'cd /project; ./gradlew build'"
LABEL org.label-schema.build-date="${BUILD_DATE}"
LABEL org.label-schema.vcs-ref="${SOURCE_COMMIT}@${SOURCE_BRANCH}"
