# Contributing to GCP DR Cold Standby Lab

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Issues

1. Check existing issues to avoid duplicates
2. Use the issue template
3. Include:
   - Terraform version
   - GCP region
   - Error message
   - Steps to reproduce

### Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Test your changes
5. Commit: `git commit -m "Add feature X"`
6. Push: `git push origin feature/my-feature`
7. Create Pull Request

### Code Style

- **Terraform**: Follow [HashiCorp style guide](https://www.terraform.io/docs/language/syntax/style.html)
- **Bash**: Use shellcheck for linting
- **Python**: Follow PEP 8

### Testing

Before submitting:

```bash
# Format Terraform
terraform fmt -recursive

# Validate Terraform
terraform validate

# Test deployment
./scripts/deploy.sh --plan
```

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/gcp-dr-cold-standby-lab.git
cd gcp-dr-cold-standby-lab

# Create branch
git checkout -b feature/your-feature

# Make changes and test
./scripts/setup.sh
./scripts/deploy.sh --plan
```

## Questions?

Open a discussion or issue if you have questions.

Thank you for contributing! 🎉
