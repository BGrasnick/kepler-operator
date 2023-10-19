#!/usr/bin/env bash
#
# This file is part of the Kepler project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright 2023 The Kepler Contributors
#

set -eu -o pipefail

# constants
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
GOOS="$(go env GOOS)"
GOARCH="$(go env GOARCH)"

declare -r PROJECT_ROOT GOOS GOARCH
declare -r LOCAL_BIN="$PROJECT_ROOT/tmp/bin"

# versions
declare -r KUSTOMIZE_VERSION=${KUSTOMIZE_VERSION:-v3.8.7}
declare -r CONTROLLER_TOOLS_VERSION=${CONTROLLER_TOOLS_VERSION:-v0.12.1}
declare -r OPERATOR_SDK_VERSION=${OPERATOR_SDK_VERSION:-v1.27.0}
declare -r YQ_VERSION=${YQ_VERSION:-v4.34.2}
declare -r CRDOC_VERSION=${CRDOC_VERSION:-v0.6.2}
declare -r OC_VERSION=${OC_VERSION:-4.13.0}
declare -r SHFMT_VERSION=${SHFMT_VERSION:-v3.7.0}

# install
declare -r KUSTOMIZE_INSTALL_SCRIPT="https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
declare -r OPERATOR_SDK_INSTALL="https://github.com/operator-framework/operator-sdk/releases/download/$OPERATOR_SDK_VERSION/operator-sdk_${GOOS}_${GOARCH}"
declare -r YQ_INSTALL="https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_${GOOS}_${GOARCH}"
declare -r OC_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OC_VERSION"

source "$PROJECT_ROOT/hack/utils.bash"

install_kustomize() {
	command -v kustomize >/dev/null 2>&1 &&
		[[ $(kustomize version --short | grep -o 'v[0-9].[0-9].[0-9]') == "$KUSTOMIZE_VERSION" ]] && {
		ok "kustomize $KUSTOMIZE_VERSION is already installed"
		return 0
	}

	info "installing kustomize version: $KUSTOMIZE_VERSION"
	(
		# NOTE: this handles softlinks properly
		cd "$LOCAL_BIN"
		curl -Ss $KUSTOMIZE_INSTALL_SCRIPT | bash -s -- "${KUSTOMIZE_VERSION:1}" .
	) || {
		fail "failed to install kustomize"
		return 1
	}
	ok "kustomize was installed successfully"
}

install_controller-gen() {
	command -v controller-gen >/dev/null 2>&1 &&
		[[ $(controller-gen --version) == "Version: $CONTROLLER_TOOLS_VERSION" ]] && {
		ok "controller-gen is already installed"
		return 0
	}

	info "installing controller-gen with version: $CONTROLLER_TOOLS_VERSION"
	GOBIN=$LOCAL_BIN \
		go install sigs.k8s.io/controller-tools/cmd/controller-gen@"$CONTROLLER_TOOLS_VERSION" || {
		fail "failed to install controller-gen"
		return 1
	}
	ok "controller-gen was installed successfully"
}

install_operator-sdk() {
	local version_regex="operator-sdk version: \"$OPERATOR_SDK_VERSION\""

	command -v operator-sdk >/dev/null 2>&1 &&
		[[ $(operator-sdk version) =~ $version_regex ]] && {
		ok "operator-sdk is already installed"
		return 0
	}

	info "installing operator-sdk with version: $OPERATOR_SDK_VERSION"
	curl -sSLo "$LOCAL_BIN/operator-sdk" "$OPERATOR_SDK_INSTALL" || {
		fail "failed to install operator-sdk"
		return 1
	}
	chmod +x "$LOCAL_BIN/operator-sdk"
	ok "operator-sdk was installed successfully"
}

install_govulncheck() {
	command -v govulncheck >/dev/null 2>&1 && {
		ok "govulncheck is already installed"
		return 0
	}
	info "installing go-vulncheck"
	go install golang.org/x/vuln/cmd/govulncheck@latest
}

install_yq() {
	local version_regex="version $YQ_VERSION"

	command -v yq >/dev/null 2>&1 &&
		[[ $(yq --version) =~ $version_regex ]] && {
		ok "yq is already installed"
		return 0
	}

	info "installing yq with version: $YQ_VERSION"
	curl -sSLo "$LOCAL_BIN/yq" "$YQ_INSTALL" || {
		fail "failed to install yq"
		return 1
	}
	chmod +x "$LOCAL_BIN/yq"
	ok "yq was installed successfully"
}

go_install() {
	local pkg="$1"
	local version="$2"
	shift 2

	info "installing $pkg version: $version"

	GOBIN=$LOCAL_BIN \
		go install "$pkg@$version" || {
		fail "failed to install $pkg - $version"
		return 1
	}
	ok "$pkg - $version was installed successfully"

}

validate_verison() {
	local cmd="$1"
	local version_arg="$2"
	local version_regex="$3"
	shift 3

	command -v "$cmd" >/dev/null 2>&1 || return 1
	[[ $(eval "$cmd $version_arg" | grep -o "$version_regex") =~ $version_regex ]] || {
		return 1
	}

	ok "$cmd installed successfully"
}
install_shfmt() {
	validate_verison shfmt --version "$SHFMT_VERSION" && {
		return 0
	}
	go_install mvdan.cc/sh/v3/cmd/shfmt "$SHFMT_VERSION"
}

install_crdoc() {
	local version_regex="version $CRDOC_VERSION"

	command -v crdoc >/dev/null 2>&1 &&
		[[ $(crdoc --version) =~ $version_regex ]] && {
		ok "crdoc is already installed"
		return 0
	}

	info "installing crdoc with version: $CRDOC_VERSION"
	GOBIN=$LOCAL_BIN \
		go install "fybrik.io/crdoc@$CRDOC_VERSION" || {
		fail "failed to install crdoc"
		return 1
	}
	ok "crdoc was installed successfully"
}

install_oc() {
	local version=" $OC_VERSION"

	command -v oc >/dev/null 2>&1 &&
		[[ $(oc version --client -oyaml | grep releaseClientVersion | cut -f2 -d:) == "$version" ]] && {
		ok "oc is already installed"
		return 0
	}

	info "installing oc version: $OC_VERSION"
	local os="$GOOS"
	[[ $os == "darwin" ]] && os="mac"

	local install="$OC_URL/openshift-client-$os.tar.gz"
	curl -sNL "$install" | tar -xzf - -C "$LOCAL_BIN" || {
		fail "failed to install oc"
		return 1
	}
	chmod +x "$LOCAL_BIN/oc"
	ok "oc was installed successfully"

}

install_all() {
	info "installing all tools ..."
	local ret=0
	for tool in $(declare -F | cut -f3 -d ' ' | grep install_ | grep -v 'install_all'); do
		"$tool" || ret=1
	done
	return $ret
}

main() {
	local op="${1:-all}"
	shift || true

	mkdir -p "$LOCAL_BIN"
	export PATH="$LOCAL_BIN:$PATH"
	install_"$op"
}

main "$@"
