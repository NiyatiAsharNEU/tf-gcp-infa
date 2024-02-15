# tf-gcp-infa

Assignment03 - 03 Terraform
Infrastructure as Code

Overview:
Terraform creates and manages resources on cloud platforms and other services through their application programming interfaces (APIs). Providers enable Terraform to work with virtually any platform or service with an accessible API.Infrastructure as Code (IaC) tools allow you to manage infrastructure with configuration files rather than through a graphical user interface. IaC allows you to build, change, and manage your infrastructure in a safe, consistent, and repeatable way by defining resource configurations that you can version, reuse, and share.

GCP accounts
Properly configured GCP credentials

Installation
Clone the Repository:
Clone the repository to your local machine.

GCP installation required
Install gcloud supporting your machine
Run the following commands for the setup process
./google-cloud-sdk/install.sh
./google-cloud-sdk/install.sh --help
./google-cloud-sdk/bin/gcloud init

gcloud auth login: Authorize Google Cloud access for the gcloud CLI with Google Cloud user credentials and set the current account as active.

Terraform Installation Instructions

Homebrew is a free and open-source package management system for Mac OS X. Install the official Terraform formula from the terminal.

First, install the HashiCorp tap, a repository of all our Homebrew packages.

brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew update
brew upgrade hashicorp/tap/terraform
terraform -help
touch ~/.bashrc
terraform -install-autocomplete

Commands to run terraform
terraform init
terraform plan
terraform apply
terraform destroy

