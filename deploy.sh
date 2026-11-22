#!/usr/bin/env bash
# Usage: ADMIN_EMAIL=you@example.com ADMIN_PASSWORD='Str0ngPass1' ./deploy.sh
#        ./deploy.sh destroy
set -euo pipefail
cd "$(dirname "$0")"
STACK=${STACK:-student-analytics-dev}
REGION=${AWS_REGION:-$(aws configure get region)}
export AWS_DEFAULT_REGION=$REGION
out() { aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

if [ "${1:-}" = "destroy" ]; then
  aws s3 rm "s3://$(out DataBucketName)" --recursive
  aws s3 rm "s3://$(out DashboardBucketName)" --recursive
  aws cloudformation delete-stack --stack-name "$STACK"
  aws cloudformation wait stack-delete-complete --stack-name "$STACK"
  echo "Stack $STACK deleted."; exit 0
fi

: "${ADMIN_EMAIL:?Set ADMIN_EMAIL}"; : "${ADMIN_PASSWORD:?Set ADMIN_PASSWORD (8+ chars, upper, lower, number)}"
python3 build_template.py
aws cloudformation validate-template --template-body file://cloudformation/template.yaml > /dev/null
aws cloudformation deploy --stack-name "$STACK" --template-file cloudformation/template.yaml \
  --capabilities CAPABILITY_IAM --parameter-overrides AdminEmail="$ADMIN_EMAIL" \
  --tags Project=student-performance-analytics Environment=dev Owner=student Purpose=analytics-dashboard

aws cognito-idp admin-set-user-password --user-pool-id "$(out UserPoolId)" --username "$ADMIN_EMAIL" --password "$ADMIN_PASSWORD" --permanent
aws s3 cp data/sample_student_data.csv "s3://$(out DataBucketName)/raw/sample_student_data.csv"
cat > dashboard/config.js <<CFG
window.APP_CONFIG={region:"$REGION",apiUrl:"$(out HttpApiUrl)",wsUrl:"$(out WebSocketUrl)",clientId:"$(out UserPoolClientId)"};
CFG
aws s3 sync dashboard "s3://$(out DashboardBucketName)" --delete
echo "Dashboard: $(out DashboardUrl)   (sign in as $ADMIN_EMAIL)"
