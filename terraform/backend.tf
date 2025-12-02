# -----------------------------
# Terraform backend config
# -----------------------------
terraform {
  backend "s3" {
    bucket         = "cloud-fun-facts-generator-bucket"
    key            = "terraform.tfstate"
    encrypt        = true
    region         = "ap-south-1"
  }
}