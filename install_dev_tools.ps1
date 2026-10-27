# Serenut OS - Yeni PC Otomatik Gelistirici Ortami Kurulumu
# Bu betik Windows Package Manager (winget) kullanarak gerekli tum araclari kurar.

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   SERENUT OS - GELISTIRICI ORTAMI KURULUMU BASLIYOR      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Git Kurulumu
Write-Host "`n[1/5] Git yukleniyor..." -ForegroundColor Yellow
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent

# 2. Node.js LTS Kurulumu
Write-Host "`n[2/5] Node.js LTS yukleniyor..." -ForegroundColor Yellow
winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent

# 3. Python 3.11 Kurulumu
Write-Host "`n[3/5] Python 3.11 yukleniyor..." -ForegroundColor Yellow
winget install --id Python.Python.3.11 -e --source winget --accept-package-agreements --accept-source-agreements --silent

# 4. Visual Studio 2022 C++ Build Tools (Windows Flutter Masaustu icin)
Write-Host "`n[4/5] Visual Studio 2022 Build Tools (C++ Araclari) yukleniyor (bu biraz zaman alabilir)..." -ForegroundColor Yellow
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" --accept-package-agreements --accept-source-agreements

# 5. Flutter SDK Kurulumu
Write-Host "`n[5/5] Flutter SDK yukleniyor..." -ForegroundColor Yellow
winget install --id Google.Flutter -e --source winget --accept-package-agreements --accept-source-agreements --silent

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   KURULUM TAMAMLANDI!                                    " -ForegroundColor Green
Write-Host "   Lutfen ortam degiskenlerinin (PATH) aktiflesmesi icin   " -ForegroundColor Green
Write-Host "   terminali veya bilgisayari yeniden baslatin.           " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
