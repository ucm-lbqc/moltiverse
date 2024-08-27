#!/bin/bash

set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Miniconda if not already installed
install_miniconda() {
    if ! command_exists conda; then
        echo "Installing Miniconda..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
        bash miniconda.sh -b -p $HOME/miniconda
        export PATH="$HOME/miniconda/bin:$PATH"
        conda init bash
        source $HOME/.bashrc
    fi
}

# Create and activate Conda environment
create_conda_env() {
    local env_name="moltiverse"
    
    if conda info --envs | grep -q "^$env_name "; then
        echo "Conda environment '$env_name' already exists."
        echo "Choose an option:"
        echo "1) Remove existing environment and create a new one"
        echo "2) Use a different name for the new environment"
        read -p "Enter your choice (1 or 2): " env_choice

        case $env_choice in
            1)
                echo "Removing existing environment..."
                conda env remove -n $env_name -y
                ;;
            2)
                read -p "Enter a new name for the Conda environment: " new_env_name
                env_name=$new_env_name
                ;;
            *)
                echo "Invalid choice. Exiting."
                exit 1
                ;;
        esac
    fi

    echo "Creating Conda environment '$env_name'..."
    conda create -n $env_name python=3.9 -y
    conda activate $env_name
}

# Install dependencies
install_dependencies() {
    conda install -c conda-forge ambertools=23 openbabel xtb -y
}

# Install Crystal
install_crystal() {
    curl -fsSL https://crystal-lang.org/install.sh | sudo bash
}

# Download and install Moltiverse from the latest release
install_moltiverse_release() {
    echo "Installing Moltiverse from the latest release..."
    
    # Get the latest release URL
    LATEST_RELEASE_URL=$(curl -s https://api.github.com/repos/ucm-lbqc/moltiverse/releases/latest | grep "tarball_url" | cut -d '"' -f 4)
    
    # Create a temporary directory
    TEMP_DIR=$(mktemp -d)
    
    # Download and extract the latest release
    curl -L ${LATEST_RELEASE_URL} | tar xz -C ${TEMP_DIR}
    
    # Move to the extracted directory
    cd ${TEMP_DIR}/*moltiverse*
    
    # Build Moltiverse
    shards build moltiverse
    
    # Move the built binary to a permanent location
    mkdir -p $HOME/moltiverse/bin
    mv bin/moltiverse $HOME/moltiverse/bin/
    
    # Clean up
    cd $HOME
    rm -rf ${TEMP_DIR}
}

# Clone and build Moltiverse from the main branch
install_moltiverse_main() {
    echo "Installing Moltiverse from the main branch..."
    git clone https://github.com/ucm-lbqc/moltiverse.git $HOME/moltiverse
    cd $HOME/moltiverse
    shards build moltiverse
}

# Add Moltiverse to PATH
add_to_path() {
    echo 'export PATH="$PATH:$HOME/moltiverse/bin"' >> $HOME/.bashrc
    source $HOME/.bashrc
}

# Main installation process
main() {
    install_miniconda
    create_conda_env
    install_dependencies
    install_crystal

    # Ask user which version to install
    echo "Which version of Moltiverse would you like to install?"
    echo "1) Latest release version (recommended for stability)"
    echo "2) Main branch version (latest development version)"
    read -p "Enter your choice (1 or 2): " version_choice

    case $version_choice in
        1)
            install_moltiverse_release
            ;;
        2)
            install_moltiverse_main
            ;;
        *)
            echo "Invalid choice. Exiting."
            exit 1
            ;;
    esac

    add_to_path
    
    echo "Moltiverse has been successfully installed!"
    echo "Please restart your terminal or run 'source ~/.bashrc' to use Moltiverse."
}

main