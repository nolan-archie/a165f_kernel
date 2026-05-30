#!/bin/bash

echo "Maximizing disk space on GitHub Actions runner..."

# Remove large pre-installed tools
sudo rm -rf /usr/share/dotnet
sudo rm -rf /usr/local/lib/android
sudo rm -rf /opt/ghc
sudo rm -rf "/usr/local/share/boost"
sudo rm -rf "$AGENT_TOOLSDIRECTORY"

# Clean up apt
sudo apt-get clean
sudo apt-get autoremove -y

echo "Disk space after cleanup:"
df -h /
