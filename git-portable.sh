#!/bin/sh

# Color codes
RED='\033[0;31m'
NC='\033[0m' # No Color


die () {
	echo "${RED}$*${NC}" >&2
	exit 1
}

usage() {
	case $1 in
	create)
		usage="${RED}$2${NC}\n"
		usage+="usage: $0 create <repo> <version>\n"
		usage+="   or: $0 create -l </path/to/tarball>\n"
		echo "$usage"  1>&2
		;;
	*)
		usage="${RED}$1${NC}\n"
		usage+="usage: $0 <create|run|rebuild-test-repo|cleanup>\n"
		echo "$usage" 1>&2
	esac
	exit 1
}

create_example_repo() {
	repo_path=$1
	git=$2

	$git init $repo_path &&
	cd $repo_path &&
	echo a >a &&
	echo "after deep" >e &&
	echo "after folder1" >g &&
	echo "after x" >z &&
	mkdir folder1 folder2 deep x &&
	mkdir deep/deeper1 deep/deeper2 deep/before deep/later &&
	mkdir deep/deeper1/deepest &&
	echo "after deeper1" >deep/e &&
	echo "after deepest" >deep/deeper1/e &&
	cp a folder1 &&
	cp a folder2 &&
	cp a x &&
	cp a deep &&
	cp a deep/before &&
	cp a deep/deeper1 &&
	cp a deep/deeper2 &&
	cp a deep/later &&
	cp a deep/deeper1/deepest &&
	cp -r deep/deeper1/deepest deep/deeper2 &&
	mkdir deep/deeper1/0 &&
	mkdir deep/deeper1/0/0 &&
	touch deep/deeper1/0/1 &&
	touch deep/deeper1/0/0/0 &&
	>folder1- &&
	>folder1.x &&
	>folder10 &&
	cp -r deep/deeper1/0 folder1 &&
	cp -r deep/deeper1/0 folder2 &&
	echo >>folder1/0/0/0 &&
	echo >>folder2/0/1 &&
	$git add . &&
	$git commit -m "initial commit" &&
	$git checkout -b base &&
	for dir in folder1 folder2 deep
	do
		$git checkout -b update-$dir base &&
		echo "updated $dir" >$dir/a &&
		$git commit -a -m "update $dir" || return 1
	done &&

	$git checkout -b rename-base base &&
	cat >folder1/larger-content <<-\EOF &&
	matching
	lines
	help
	inexact
	renames
	EOF
	cp folder1/larger-content folder2/ &&
	cp folder1/larger-content deep/deeper1/ &&
	$git add . &&
	$git commit -m "add interesting rename content" &&

	$git checkout -b rename-out-to-out rename-base &&
	mv folder1/a folder2/b &&
	mv folder1/larger-content folder2/edited-content &&
	echo >>folder2/edited-content &&
	echo >>folder2/0/1 &&
	echo stuff >>deep/deeper1/a &&
	$git add . &&
	$git commit -m "rename folder1/... to folder2/..." &&

	$git checkout -b rename-within-sparse rename-base &&
	mv folder1/larger-content folder1/edited-content &&
	$git add . &&
	$git commit -m "rename folder1/larger-content to folder1/edited-content"

	$git checkout -b rename-out-to-in rename-base &&
	mv folder1/a deep/deeper1/b &&
	echo more stuff >>deep/deeper1/a &&
	rm folder2/0/1 &&
	mkdir folder2/0/1 &&
	echo >>folder2/0/1/1 &&
	mv folder1/larger-content deep/deeper1/edited-content &&
	echo >>deep/deeper1/edited-content &&
	$git add . &&
	$git commit -m "rename folder1/... to deep/deeper1/..." &&

	$git checkout -b rename-in-to-out rename-base &&
	mv deep/deeper1/a folder1/b &&
	echo >>folder2/0/1 &&
	rm -rf folder1/0/0 &&
	echo >>folder1/0/0 &&
	mv deep/deeper1/larger-content folder1/edited-content &&
	echo >>folder1/edited-content &&
	$git add . &&
	$git commit -m "rename deep/deeper1/... to folder1/..." &&

	$git checkout -b df-conflict-1 base &&
	rm -rf folder1 &&
	echo content >folder1 &&
	$git add . &&
	$git commit -m "dir to file" &&

	$git checkout -b df-conflict-2 base &&
	rm -rf folder2 &&
	echo content >folder2 &&
	$git add . &&
	$git commit -m "dir to file" &&

	$git checkout -b fd-conflict base &&
	rm a &&
	mkdir a &&
	echo content >a/a &&
	$git add . &&
	$git commit -m "file to dir" &&

	for side in left right
	do
		$git checkout -b merge-$side base &&
		echo $side >>deep/deeper2/a &&
		echo $side >>folder1/a &&
		echo $side >>folder2/a &&
		$git add . &&
		$git commit -m "$side" || return 1
	done &&

	$git checkout -b deepest base &&
	echo "updated deepest" >deep/deeper1/deepest/a &&
	$git commit -a -m "update deepest" &&

	$git checkout -f base &&
	$git reset --hard
}

main() {
	case $1 in
	create)
		shift

		# Parse options
		POSITIONAL=()
		while [[ $# -gt 0 ]]; do
			key="$1"

			case $key in
				-l|--local)
					local_tar=1
					shift # past argument
					;;
				*)
					POSITIONAL+=("$1") # save it in an array for later
					shift # past argument
					;;
			esac
		done

		if [[ $local_tar -eq 1 ]]; then
			tar_path=${POSITIONAL[0]}

			if [[ -z $tar_path ]]; then
				usage create "Must provide path to source tarball"
			fi
		else
			# Download tarball to /tmp
			github_repo=${POSITIONAL[0]}
			version=${POSITIONAL[1]}

			if [[ -z $github_repo ]] || [[ -z $version ]]; then
				usage create "Must provide github repo & version"
			fi

			tar_path="/tmp/git-$version.tgz"

			echo "Downloading source $github_repo, version $version"
			curl -L -f "https://github.com/$github_repo/tarball/$version" -o "$tar_path" \
				|| die "Could not download git source code"
			echo "Downloaded source to $tar_path"
		fi

		# Untar into /tmp
		src_path=/tmp/git-sandbox/

		echo "Extracting into $src_path"
		rm -rf $src_path
		mkdir -p $src_path
		tar -xzf "$tar_path" --strip-components=1 -C $src_path

		# Build from source
		echo "Extracting git from source"
		make -C $src_path -j12 || die "Failed to build Git"

		# Install to ./sandbox
		sandbox="$(pwd)/sandbox"
		install_path="$sandbox/install"

		rm -rf $sandbox
		mkdir -p $install_path
		make -C $src_path prefix=$install_path install

		# Create test repo
		create_example_repo $sandbox/example-repo $install_path/bin/git || die "Failed to initialize sandbox repo"
		;;
	run)
		# Create terminal in sandbox repo
		# TODO: linux
		sandbox="$(pwd)/sandbox"
		install_path=$sandbox/install

		osascript -e "
			tell application \"Terminal\"
				do script \"export PATH='$install_path/bin:$PATH' && export PS1='(git-sandbox) \$ ' && cd $sandbox && printf '\\\33c\\\e[3J'\"
				activate
			end tell
			"
		;;
	rebuild-example-repo)
		# Create example repo
		sandbox="$(pwd)/sandbox"
		install_path=$sandbox/install
		create_example_repo $sandbox/example-repo $install_path/bin/git || die "Failed to initialize sandbox repo"
		;;
	cleanup)
		# Delete everything
		sandbox="$(pwd)/sandbox"
		rm -rf $sandbox
		;;
	*)
		if [[ -z $1 ]]; then
			usage "Please specify a command"
		else
			usage "Not a valid command: $1"
		fi
	esac
}

main $@