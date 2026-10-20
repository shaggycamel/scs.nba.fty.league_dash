DEPLOY_ENV_FILE="${SCS_DEPLOY_ENV:-$HOME/.config/scs_deploy.env}"
if [ -f "$DEPLOY_ENV_FILE" ]; then
  # shellcheck source=/dev/null
  . "$DEPLOY_ENV_FILE"
fi
