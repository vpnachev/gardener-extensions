#!/bin/bash
#
# Copyright (c) 2019 SAP SE or an SAP affiliate company. All rights reserved. This file is licensed under the Apache Software License, v. 2 except as noted otherwise in the LICENSE file
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -e

DIRNAME="$(echo "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )")"
source "$DIRNAME/common.sh"

function usage {
    cat <<EOM
Usage:
generate-controller-registration <name> <chart-dir> <dest> <kind-and-type> [kinds-and-types ...]

    <name>            Name of the controller registration to generate.
    <type>            Type of the controller registration.
    <chart-dir>       Location of the chart directory.
    <dest>            The destination file to write the registration YAML to.
    <kind-and-type>   A tuple of kind and type of the controller registration to generate.
                      Separated by ':'.
                      Example: OperatingSystemConfig:os-coreos
    <kinds-and-types> Further tuples of kind and type of the controller registration to generate.
                      Separated by ':'.
EOM
    exit 0
}

NAME="$1"
CHART_DIR="$2"
DEST="$3"
KIND_AND_TYPE="$4"

( [[ -z "$NAME" ]] || [[ -z "$CHART_DIR" ]] || [[ -z "$DEST" ]] || [[ -z "$KIND_AND_TYPE" ]]) && usage

KINDS_AND_TYPES=("$KIND_AND_TYPE" "${@:5}")

# The following code is to make `helm package` idempotent: Usually, everytime `helm package` is invoked,
# it produces a different `.tgz` due to modification timestamps and some special shasums of gzip. We
# resolve this by unarchiving the `.tgz`, compressing it again with a constant `mtime` and no gzip
# checksums.
temp_dir="$(mktemp -d)"
temp_helm_home="$(mktemp -d)"
temp_extract_dir="$(mktemp -d)"
function cleanup {
    rm -rf "$temp_dir"
    rm -rf "$temp_helm_home"
    rm -rf "$temp_extract_dir"
}
trap cleanup EXIT ERR INT TERM

export HELM_HOME="$temp_helm_home"
helm init --client-only > /dev/null 2>&1
helm package "$CHART_DIR" --version "$VERSION" --app-version "$VERSION" --destination "$temp_dir" > /dev/null
tar -xzm -C "$temp_extract_dir" -f "$temp_dir"/*
chart="$(tar --sort=name -c --owner=root:0 --group=root:0 --mtime='UTC 2019-01-01' -C "$temp_extract_dir" "$(basename "$temp_extract_dir"/*)" | gzip -n | base64 | tr -d '\n')"

mkdir -p "$(dirname "$DEST")"

cat <<EOM > "$DEST"
---
apiVersion: core.gardener.cloud/v1alpha1
kind: ControllerRegistration
metadata:
  name: $NAME
spec:
  resources:
EOM

for kind_and_type in "${KINDS_AND_TYPES[@]}"; do
  KIND="$(echo "$kind_and_type" | cut -d ':' -f 1)"
  TYPE="$(echo "$kind_and_type" | cut -d ':' -f 2)"
  cat <<EOM >> "$DEST"
  - kind: $KIND
    type: $TYPE
EOM
done

cat <<EOM >> "$DEST"
  deployment:
    type: helm
    providerConfig:
      chart: $chart
      values:
        image:
          tag: $VERSION
EOM

echo "Successfully generated controller registration at $DEST"
