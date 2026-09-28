#!/bin/bash

set -euo pipefail

COPY=0

# GIT_NAME=${1:-}
# TAG=${2:-}
# 
# if [ -z "$GIT_NAME" ] || [ -z "$TAG" ]; then
#     echo "Error: You must specify a git repository name and tag."
#     echo "Usage: $0 GIT_NAME TAG"
#     exit 1
# fi

if [ $# -eq 2 ]; then
	GIT_NAME="$1"
	TAG="$2"
elif [ $# -eq 1 ]; then
	GIT_NAME="$(basename "$(pwd)")"
	TAG="$1"
else
	echo "Usage: $0 [GIT_NAME] TAG"
	exit 1
fi



# REPO_HOST=${REPO_HOST:-}
# 
# if [ -z "$REPO_HOST" ]; then
#     echo "Error: You must set REPO_HOST."
#     exit 1
# fi

GIT_URL="https://github.com/rrasch/$GIT_NAME"

latest_git_tag()
{
	git ls-remote --tags "$1" |
		awk -F/ '$2 == "tags" && $NF !~ /\^\{\}$/ { print $NF }' |
		sort -V |
		tail -n 1
}

git_tag_commit()
{
	git ls-remote "$1" "refs/tags/$2" | cut -f1 | cut -c1-7
}

if [ "$TAG" = "0.0.0" ] || [ "$TAG" = "v0.0.0" ]; then
	if [ "$GIT_NAME" = "hocr-tools" ]; then
		git switch rtl
	fi
	COMMIT=$(git rev-parse --short HEAD)
	PROD_BUILD=0
elif [[ "${TAG,,}" == "latest" ]]; then
	TAG=$(latest_git_tag "$GIT_URL")
	COMMIT=$(git_tag_commit "$GIT_URL" "$TAG")
	PROD_BUILD=1
	echo "Latest tag for $GIT_NAME is $TAG ($COMMIT)"
else
	COMMIT=$(git_tag_commit "$GIT_URL" "$TAG")
	PROD_BUILD=1
fi

if [ -z "$COMMIT" ]; then
	echo "ERROR: Tag '$TAG' not found in repository '$GIT_URL'" >&2
	exit 1
fi

echo "Building $GIT_NAME:"
echo "  Repo:   $GIT_URL"
echo "  Tag:    $TAG"
echo "  Commit: $COMMIT"

source /etc/os-release

if [[ "$ID" == "rhel" ]]; then
	VERSION="${VERSION_ID%%.*}"   # major only
else
	VERSION="$VERSION_ID"         # full version (Fedora, etc.)
fi

OSVER="${ID}${VERSION}"

REPO_DIR=/content/prod/rstar/repo/publishing/$VERSION

RPM_DIR=$REPO_DIR/RPMS/noarch

rm -vf $RPM_DIR/$GIT_NAME-*rpm

pushd ~/work/$GIT_NAME
git pull
popd

rpmbuild -bb $GIT_NAME.spec \
	--define "git_tag $TAG" \
	--define "git_commit $COMMIT" 2>&1 | tee build-${TAG}-${OSVER}.log

sudo dnf -y remove $GIT_NAME

sudo dnf -y install $RPM_DIR/$GIT_NAME-*rpm

createrepo --update $REPO_DIR

if (( PROD_BUILD && COPY )); then
	read -r -p "Repository host: " REPO_HOST

	if [[ -z "$REPO_HOST" ]]; then
		echo "Repository host is required." >&2
		exit 1
	fi

	scp $RPM_DIR/$GIT_NAME-*.rpm $REPO_HOST:$RPM_DIR

	if [[ -z "$REPO_HOST" ]]; then
		echo "Repository host is required." >&2
		exit 1
	fi

	ssh "$REPO_HOST" createrepo --update $REPO_DIR
fi
