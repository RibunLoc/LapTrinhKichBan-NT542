terraform {
  # Remote state backend (S3-compatible). We use DigitalOcean Spaces in CI.
  # Config is supplied at runtime via `terraform init -backend-config=...`.
  backend "s3" {}
}

