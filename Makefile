check:
	sh -n install.sh
	shellcheck install.sh
	bash -n docker-stale-cleanup.sh
	shellcheck docker-stale-cleanup.sh
	sh -n tests/docker-stale-cleanup-install.sh
	shellcheck tests/docker-stale-cleanup-install.sh
	sh tests/docker-stale-cleanup-install.sh
