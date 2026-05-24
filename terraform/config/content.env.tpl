GITSYNC_REPO=git@github.com:${github_org}/${content_repo}.git
GITSYNC_REF=${content_branch}
GITSYNC_ROOT=${data_dir}
GITSYNC_LINK=content
# depth=1 is v4 default
GITSYNC_DEPTH="1"
# the number of seconds between syncs (default 1s)
GITSYNC_PERIOD="60s"
# using secret and configmap for cloning over SSH
GITSYNC_SSH="true"
GITSYNC_SSH_KEY_FILE=/home/git-sync/.ssh/content-deploy-key.pem
GITSYNC_SSH_KNOWN_HOSTS_FILE=/home/git-sync/.ssh/known_hosts
# # OVERRIDE DEFAULTS IF NOT WORKING
# GITSYNC_ADD_USER="true"
# GITSYNC_SSH_KNOWN_HOSTS="false"
