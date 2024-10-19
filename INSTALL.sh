#!/bin/bash

FORCE_INTERACTIVE=${FORCE_INTERACTIVE:-0}
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if libyaml-dev is installed
check_libyaml_dev() {
    # Check using dpkg if available (Debian-based systems)
    if command_exists dpkg; then
        if dpkg -s libyaml-dev >/dev/null 2>&1; then
        echo "libyaml-dev is installed. (dpkg check)"
            return 0  # libyaml-dev is installed
        fi
    fi

    if [ -f "/usr/include/yaml.h" ]; then
        echo "libyaml-dev is installed. (yaml.h check)"
        return 0  # File exists, libyaml-dev is likely installed
    elif ldconfig -p | grep -q "libyaml"; then
        echo "libyaml-dev is installed. (ldconfig check)"
        return 0  # libyaml is in the library cache
    else
        return 1  # libyaml-dev is likely not installed
    fi
}

check_system_dependencies() {
    echo "Checking system dependencies..."
    local missing_deps=()
    
    # Check for commands
    for cmd in git curl wget dpkg; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for libyaml-dev
    echo "Checking for libyaml-dev..."
    if ! check_libyaml_dev; then
        missing_deps+=("libyaml-dev")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "The following dependencies are missing: ${missing_deps[*]}"
        echo "Please install them using your distribution's package manager."
        echo "For example, on Ubuntu or Debian, you can use:"
        echo "sudo apt-get update && sudo apt-get install ${missing_deps[*]}"
        exit 1
    fi
}

# Function to check if Conda (Miniconda or Anaconda) is installed
conda_check() {
    if command_exists conda; then
        echo "Conda is already installed."
        return 0
    elif [ -d "$HOME/miniconda3" ]; then
        echo "Miniconda is installed but not in PATH. Adding to PATH..."
        export PATH="$HOME/miniconda3/bin:$PATH"
        return 0
    elif [ -d "$HOME/anaconda3" ]; then
        echo "Anaconda is installed but not in PATH. Adding to PATH..."
        export PATH="$HOME/anaconda3/bin:$PATH"
        return 0
    else
        return 1
    fi
}

# Install Miniconda if not already installed
install_miniconda() {
    if conda_check; then
        echo "Using existing Conda installation."
    else
        echo "Installing Miniconda..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
        bash miniconda.sh -b -p $HOME/miniconda3
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi
    
    # Initialize conda for bash
    conda init bash
    
    # Source the bashrc to apply changes immediately
    source $HOME/.bashrc
    
    # Ensure conda command is available
    eval "$(conda shell.bash hook)"
}

# Create and activate Conda environment
create_conda_env() {
    local env_name="moltiverse"

    if conda info --envs | grep -q "^$env_name "; then
        if [ -t 0 ]; then  # Check if the script is running in an interactive shell
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
        else
            echo "Non-interactive mode: Removing existing environment '$env_name' and creating a new one."
            conda env remove -n $env_name -y
        fi
    fi

    echo "Creating Conda environment '$env_name'..."
    conda create -n $env_name -y
    # Activate the environment
    eval "$(conda shell.bash hook)"
    conda activate $env_name
}

# Install dependencies
install_dependencies() {
    echo "Installing dependencies..."
    conda install -c conda-forge ambertools=23 openbabel xtb -y
}

# Install Crystal
install_crystal() {
    if command_exists crystal; then
        current_version=$(crystal --version | grep Crystal | awk '{print $2}')
        echo "Crystal version $current_version is already installed."
        
        if [ "$current_version" = "1.13.1" ]; then
            echo "The required version (1.13.1) is already installed. Skipping Crystal installation."
            return
        fi
        
        if [ -t 0 ] || [ "$FORCE_INTERACTIVE" = "1" ]; then
            read -p "Do you want to proceed with installation of version 1.13.1? (y/n): " proceed
            if [[ $proceed != "y" ]]; then
                echo "Skipping Crystal installation."
                return
            fi
        else
            echo "Non-interactive mode: Proceeding with Crystal 1.13.1 installation."
        fi
    fi

    echo "Installing Crystal version 1.13.1..."
    
    wget https://github.com/crystal-lang/crystal/releases/download/1.13.1/crystal-1.13.1-1-linux-x86_64.tar.gz
    sudo tar -xvf crystal-1.13.1-1-linux-x86_64.tar.gz -C /opt/
    sudo ln -sf /opt/crystal-1.13.1-1/bin/crystal /usr/local/bin/crystal
    sudo ln -sf /opt/crystal-1.13.1-1/bin/shards /usr/local/bin/shards
    rm crystal-1.13.1-1-linux-x86_64.tar.gz
    
    echo "Crystal 1.13.1 has been installed successfully."
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
    shards build moltiverse --release
    
    # Move the built binary to a permanent location
    mkdir -p $HOME/moltiverse/bin
    mv -f bin/moltiverse $HOME/moltiverse/bin/
    
    # Clean up
    cd $HOME
    rm -rf ${TEMP_DIR}
}

# Clone and build Moltiverse from the main branch
install_moltiverse_main() {
    echo "Installing Moltiverse from the main branch..."
    
    # Check if the moltiverse directory exists
    if [ -d "$HOME/moltiverse" ]; then
        echo "Existing Moltiverse directory found. Removing it..."
        rm -rf "$HOME/moltiverse"
    fi
    
    # Clone the repository
    git clone https://github.com/ucm-lbqc/moltiverse.git "$HOME/moltiverse"
    
    # Change to the moltiverse directory
    cd "$HOME/moltiverse"
    
    # Build moltiverse
    shards build moltiverse --release
}

# Add Moltiverse to PATH
add_to_path() {
    echo 'export PATH="$PATH:$HOME/moltiverse/bin"' >> $HOME/.bashrc
    source $HOME/.bashrc
}

# Main installation process
main() {
    check_system_dependencies
    install_miniconda
    create_conda_env
    install_dependencies
    install_crystal

    if [ -t 0 ] || [ "$FORCE_INTERACTIVE" = "1" ]; then
        # Interactive mode
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
                echo "Invalid choice. Defaulting to main branch version."
                install_moltiverse_main
                ;;
        esac
    else
        # Non-interactive mode
        # TO:DO: Add a flag to specify the version to install
        # Defaulting to main branch version for now, but in the future the default should be the latest release version.
        echo "Non-interactive mode: Installing main branch version of Moltiverse."
        install_moltiverse_main
    fi

    add_to_path

    echo " "
    echo "=========================================================================="
    echo "Moltiverse has been successfully installed!"
    echo "Please restart your terminal or run 'source ~/.bashrc' to use Moltiverse."
}

main
