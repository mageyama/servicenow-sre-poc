#!/bin/bash
set -euo pipefail

#=============================================================================
# GCP Setup Script for ServiceNow SRE PoC
# - Artifact Registry リポジトリ作成
# - GitHub Actions 用サービスアカウント作成
# - Workload Identity Federation (WIF) 設定
# - サービスアカウントへの権限付与
#=============================================================================

# ============== 変数設定（必要に応じて変更） ==============
PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project-id}"
REGION="${GCP_REGION:-asia-northeast1}"
REPO_NAME="servicenow-sre-poc"
SA_NAME="github-actions-sa"
SA_DISPLAY_NAME="GitHub Actions Service Account"
WIF_POOL_NAME="github-actions-pool"
WIF_PROVIDER_NAME="github-actions-provider"
GITHUB_OWNER="${GITHUB_OWNER:-Kota-and-the-repo-owner}"
GITHUB_REPO="${GITHUB_REPO:-servicenow-sre-poc}"

# ============== 導出される変数 ==============
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
WIF_POOL_ID="projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${WIF_POOL_NAME}"
WIF_PROVIDER_ID="${WIF_POOL_ID}/providers/${WIF_PROVIDER_NAME}"

echo "======================================"
echo "GCP Setup for ServiceNow SRE PoC"
echo "======================================"
echo "Project ID:    ${PROJECT_ID}"
echo "Region:        ${REGION}"
echo "GitHub Repo:   ${GITHUB_OWNER}/${GITHUB_REPO}"
echo "SA Email:      ${SA_EMAIL}"
echo "======================================"
echo ""

# プロジェクトを設定
echo ">>> Setting project to ${PROJECT_ID}..."
gcloud config set project "${PROJECT_ID}"

# 必要な API を有効化
echo ">>> Enabling required APIs..."
gcloud services enable \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  iamcredentials.googleapis.com \
  iam.googleapis.com

#=============================================================================
# 1. Artifact Registry リポジトリ作成
#=============================================================================
echo ""
echo ">>> Creating Artifact Registry repository: ${REPO_NAME}..."
if gcloud artifacts repositories describe "${REPO_NAME}" \
  --location="${REGION}" &>/dev/null; then
  echo "    Repository already exists. Skipping."
else
  gcloud artifacts repositories create "${REPO_NAME}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="ServiceNow SRE PoC Docker images"
  echo "    Repository created."
fi

#=============================================================================
# 2. サービスアカウント作成
#=============================================================================
echo ""
echo ">>> Creating service account: ${SA_NAME}..."
if gcloud iam service-accounts describe "${SA_EMAIL}" &>/dev/null; then
  echo "    Service account already exists. Skipping."
else
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name="${SA_DISPLAY_NAME}" \
    --description="Service account for GitHub Actions CI/CD"
  echo "    Service account created."
fi

#=============================================================================
# 3. サービスアカウントへの権限付与
#=============================================================================
echo ""
echo ">>> Granting IAM roles to ${SA_EMAIL}..."

ROLES=(
  "roles/artifactregistry.writer"          # Artifact Registry 書き込み
  "roles/cloudbuild.builds.editor"         # Cloud Build 実行
  "roles/iam.serviceAccountUser"           # SA としてデプロイするために必要
  "roles/run.admin"                        # Cloud Run 管理
  "roles/serviceusage.serviceUsageConsumer" # GCP API 利用に必要
)

for ROLE in "${ROLES[@]}"; do
  echo "    Granting ${ROLE}..."
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet
done
echo "    IAM roles granted."

#=============================================================================
# 4. Workload Identity Federation 設定
#=============================================================================
echo ""
echo ">>> Setting up Workload Identity Federation..."

# WIF Pool 作成
echo "    Creating Workload Identity Pool: ${WIF_POOL_NAME}..."
if gcloud iam workload-identity-pools describe "${WIF_POOL_NAME}" \
  --location="global" &>/dev/null; then
  echo "    Pool already exists. Skipping."
else
  gcloud iam workload-identity-pools create "${WIF_POOL_NAME}" \
    --location="global" \
    --display-name="GitHub Actions Pool" \
    --description="Workload Identity Pool for GitHub Actions"
  echo "    Pool created."
fi

# WIF Provider 作成
echo "    Creating Workload Identity Provider: ${WIF_PROVIDER_NAME}..."
if gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_NAME}" \
  --workload-identity-pool="${WIF_POOL_NAME}" \
  --location="global" &>/dev/null; then
  echo "    Provider already exists. Skipping."
else
  gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER_NAME}" \
    --workload-identity-pool="${WIF_POOL_NAME}" \
    --location="global" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository == '${GITHUB_OWNER}/${GITHUB_REPO}'"
  echo "    Provider created."
fi

# サービスアカウントに WIF からのアクセスを許可
echo "    Binding SA to Workload Identity Pool..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WIF_POOL_ID}/attribute.repository/${GITHUB_OWNER}/${GITHUB_REPO}" \
  --quiet
echo "    WIF setup complete."

#=============================================================================
# 5. WIF Provider のフルパスを取得
#=============================================================================
echo ""
echo ">>> Retrieving Workload Identity Provider full name..."
WIF_PROVIDER_FULL=$(gcloud iam workload-identity-pools providers describe "${WIF_PROVIDER_NAME}" \
  --workload-identity-pool="${WIF_POOL_NAME}" \
  --location="global" \
  --format="value(name)")

#=============================================================================
# 6. GitHub Secrets に登録すべき値を出力
#=============================================================================
echo ""
echo "======================================"
echo " GitHub Secrets に登録する環境変数"
echo "======================================"
echo ""
echo "以下の値を GitHub リポジトリの Settings > Secrets and variables > Actions に登録してください:"
echo ""
echo "  GCP_PROJECT_ID          = ${PROJECT_ID}"
echo "  GCP_WIF_PROVIDER        = ${WIF_PROVIDER_FULL}"
echo "  GCP_SA_EMAIL            = ${SA_EMAIL}"
echo "  GCP_REGION              = ${REGION}"
echo "  GCP_AR_REPO             = ${REPO_NAME}"
echo ""
echo "--------------------------------------"
echo " GitHub Actions ワークフローでの使用例"
echo "--------------------------------------"
echo ""
echo '  - uses: google-github-actions/auth@v2'
echo '    with:'
echo '      workload_identity_provider: ${{ secrets.GCP_WIF_PROVIDER }}'
echo '      service_account: ${{ secrets.GCP_SA_EMAIL }}'
echo ""
echo "======================================"
echo " Setup complete!"
echo "======================================"
