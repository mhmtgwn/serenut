# 🛡️ Serenut OS — Security & Vulnerability Scan Pipeline

This document defines the automated container vulnerability scans, credential audits, and Software Bill of Materials (SBOM) generation checks enforced before production release.

---

## 1. Secrets and Credentials Scan (Gitleaks)
To ensure no API keys, private tokens, or JWT secrets leak into our Git history, we run Gitleaks on every commit and pull request.

### Local Installation
```bash
# Install Gitleaks using Homebrew (macOS/Linux)
brew install gitleaks

# Install Gitleaks on Windows (using scoop or download binary)
scoop install gitleaks
```

### Execution
Run the scan from the repository root:
```bash
gitleaks detect --source=. --verbose
```

### GitHub Actions Integration (`.github/workflows/gitleaks.yml`)
```yaml
name: Gitleaks Scan
on: [push, pull_request]
jobs:
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      - name: Run Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## 2. Container Vulnerability Scanning (Trivy)
All backend images built for production are scanned using Aquasec Trivy to block vulnerable base layers.

### Execution
```bash
# Scan our backend production image for Critical and High vulnerabilities
trivy image --severity CRITICAL,HIGH serenut-pos-backend:latest
```

### GitHub Actions Integration (`.github/workflows/trivy.yml`)
```yaml
name: Container Vulnerability Scan
on:
  push:
    branches: [main, production]
jobs:
  trivy-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      - name: Build local Docker Image
        run: |
          docker build -t serenut-pos-backend:latest server/
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'serenut-pos-backend:latest'
          format: 'table'
          exit-code: '1' # Fails build if CRITICAL issues are found
          ignore-unfixed: true
          severity: 'CRITICAL,HIGH'
```

---

## 3. Software Bill of Materials (SBOM) Generation
SBOM lists all libraries, binaries, and dependencies included in the build to prevent supply chain vulnerabilities.

### Generate SBOM using Trivy
```bash
# Generate SBOM in CycloneDX JSON format
trivy fs --format cyclonedx --output sbom.json server/
```

### Verification Rule
All critical dependencies must be audited monthly:
```bash
npm audit --audit-level=high
```
Any high-risk dependency must be patched or bypassed only with explicit security architecture review documentation.
