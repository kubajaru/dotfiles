#! /bin/bash

# Arguments: 
# version of Azure CLI
# kubectl version
# kubelogin version
# helm version
# k9s version

echo "Install stuff that does more stuff"
echo

sudo apt update
sudo apt install unzip zip zsh fd-find bat ripgrep apt-transport-https libxi6 libxrender1 libxtst6 mesa-utils libfontconfig libgtk-3-bin tar dbus-user-session

echo "Install Azure CLI, version: $1."
echo

sudo mkdir -p /etc/apt/keyrings
curl -sLS https://packages.microsoft.com/keys/microsoft.asc |
  gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/microsoft.gpg

AZ_DIST=$(lsb_release -cs)
echo "Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${AZ_DIST}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-by: /etc/apt/keyrings/microsoft.gpg" | sudo tee /etc/apt/sources.list.d/azure-cli.sources

sudo update
sudo apt-get install azure-cli=$1-1~${AZ_DIST}

echo "Install kubectl and kubelogin from Azure CLI, version $2 and $3 respectevly"
echo

az aks install-cli --client-version $2 --kubelogin-version $3

echo "Install helm, version $4"
echo

curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm=$4

echo "Install k9s, version latest"
echo

wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb && apt install ./k9s_linux_amd64.deb && rm k9s_linux_amd64.deb

echo "Install go, version latest"
echo

wget https://go.dev/dl/go1.25.5.linux-amd64.tar.gz -o /tmp/go1.25.5.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go1.25.5.linux-amd64.tar.gz

echo "Install sdkman for Java, latest"
echo

curl -s "https://get.sdkman.io?ci=true&rcupdate=false" | bash

echo "Configure ZSH and oh-my-zsh"
echo

chsh -s $(which zsh)
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
rm -rf ~/.zshrc
ln -s ~/repos/.zshrc ~/.zshrc

echo "Configure bat"
echo

mkdir -p ~/.local/bin
ln -s $(which batcat) ~/.local/bin/bat

echo "Configure fd"
echo

ln -s $(which fdfind) ~/.local/bin/fd

echo "Install fzf, latest"
echo

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

echo "Install VS Code, latest"
echo 

sudo apt-get install wget gpg &&
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg &&
sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg &&
rm -f microsoft.gpg

echo "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg" | sudo tee /etc/apt/sources.list.d/vscode.sources
sudo update
sudo apt install code

echo "Install JetBrains Toolbox, latest"
echo 

wget https://www.jetbrains.com/toolbox-app/download/download-thanks.html?platform=linux -o /tmp/toolbox.tar.gz
tar -xvf /tmp/toolbox.tar.gz -C ~/.local/bin 
echo "Remember to run jetbrains-toolbox"

