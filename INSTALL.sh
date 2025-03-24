#!/bin/bash

FORCE_INTERACTIVE=${FORCE_INTERACTIVE:-0}
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

LIBYAML_MESSAGE_PRINTED=0

# Function to check if libyaml-dev is installed
check_libyaml_dev() {
    local print_message=${1:-0}
    # Check using dpkg if available (Debian-based systems)
    if command_exists dpkg; then
        if dpkg -s libyaml-dev >/dev/null 2>&1; then
        [ "$print_message" -eq 1 ] && [ "$LIBYAML_MESSAGE_PRINTED" -eq 0 ] && echo "libyaml-dev is installed. (dpkg check)" && LIBYAML_MESSAGE_PRINTED=1
            return 0  # libyaml-dev is installed
        fi
    fi

    if [ -f "/usr/include/yaml.h" ]; then
        [ "$print_message" -eq 1 ] && [ "$LIBYAML_MESSAGE_PRINTED" -eq 0 ] && echo "libyaml-dev is installed. (yaml.h check)" && LIBYAML_MESSAGE_PRINTED=1
        return 0  # File exists, libyaml-dev is likely installed
    elif ldconfig -p | grep -q "libyaml"; then
        [ "$print_message" -eq 1 ] && [ "$LIBYAML_MESSAGE_PRINTED" -eq 0 ] && echo "libyaml-dev is installed. (ldconfig check)" && LIBYAML_MESSAGE_PRINTED=1
        return 0  # libyaml is in the library cache
    else
        echo "libyaml-dev is not installed."
        return 1  # libyaml-dev is likely not installed
    fi
}

check_system_dependencies() {
    echo "Checking system dependencies..."
    local missing_deps=()
    
    # Check for commands
    for cmd in git curl wget dpkg tee; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for libyaml-dev
    echo "Checking for libyaml-dev..."
    if ! check_libyaml_dev 1; then
        sudo apt-get -y install libyaml-dev
    fi

    # Check again after installing libyaml-dev
    if ! check_libyaml_dev 1; then
        missing_deps+=("libyaml-dev")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo ""
        echo "ERROR: The following dependencies are missing: ${missing_deps[*]}"
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

create_conda_env() {
    local env_name="moltiverse"

    if conda env list | grep -q "^$env_name "; then
        if [ -t 0 ] || [ "$FORCE_INTERACTIVE" = "1" ]; then
            echo "Conda environment '$env_name' already exists."
            echo "Choose an option:"
            echo "1) Remove existing environment and create a new one"
            echo "2) Use the existing environment"
            echo "3) Use a different name for the new environment"
            read -p "Enter your choice (1, 2, or 3): " env_choice

            case $env_choice in
                1)
                    echo "Removing existing environment..."
                    conda env remove -n $env_name -y
                    ;;
                2)
                    echo "Using existing environment..."
                    ;;
                3)
                    read -p "Enter a new name for the Conda environment: " new_env_name
                    env_name=$new_env_name
                    ;;
                *)
                    echo "Invalid choice. Exiting."
                    exit 1
                    ;;
            esac
        else
            echo "Non-interactive mode: Removing existing environment '$env_name'"
            conda env remove -n $env_name -y
        fi
    fi

    if ! conda create -n $env_name -y 2> >(tee /tmp/conda_error.log >&2); then
        if grep -q "CondaValueError: prefix already exists:" /tmp/conda_error.log; then
            echo "Error: Conda environment directory already exists."
            prefix_path=$(grep "CondaValueError: prefix already exists:" /tmp/conda_error.log | awk '{print $NF}')
            echo "Removing existing directory at $prefix_path"
            rm -rf "$prefix_path"
            echo "Retrying environment creation..."
            conda create -n $env_name -y
        else
            echo "Error: Failed to create Conda environment. See error log above."
            exit 1
        fi
    fi

    if ! conda env list | grep -q "^$env_name "; then
        echo "Error: Failed to create/update environment '$env_name'."
        exit 1
    fi

    # Activate the environment
    echo "Activating environment '$env_name'..."
    eval "$(conda shell.bash hook)"
    conda activate $env_name
}

# Install dependencies
install_dependencies() {
    echo "Installing dependencies..."
    conda install -c conda-forge ambertools=24 xtb python=3.13.2 -y
    # Install CDPKit via pip
    echo "Installing CDPKit..."
    pip install cdpkit==1.2.2
}

# Install Crystal
install_crystal() {
    # Check if crystal is already installed
    if command_exists crystal; then
        current_version=$(crystal --version | grep Crystal | awk '{print $2}')
        required_version="1.15.1"  # Set your minimum required version
        echo "Crystal version $current_version is already installed."
        
        # Compare versions
        if [ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" = "$required_version" ]; then
            # Current version meets or exceeds requirements
            if [ -t 0 ] || [ "$FORCE_INTERACTIVE" = "1" ]; then
                echo "Crystal $current_version meets the minimum version requirement ($required_version)."
                read -p "Do you still want to reinstall Crystal? (y/n): " proceed
                if [[ $proceed != "y" ]]; then
                    echo "Skipping Crystal installation."
                    return 0
                fi
            else
                echo "Non-interactive mode: Crystal $current_version already meets requirements. Skipping reinstallation."
                return 0
            fi
        else
            # Current version is older than required
            echo "Crystal $current_version is installed but version $required_version or newer is required."
            echo "Will attempt to upgrade Crystal."
        fi
    fi

    echo "Installing Crystal language..."
    
    # Completely remove any existing Crystal packages before installing new one
    if command_exists dpkg; then
        echo "Removing any existing Crystal packages..."
        
        # Find all crystal-related packages
        crystal_packages=$(dpkg -l | grep -E 'crystal[0-9\.]*' | awk '{print $2}')
        
        if [ -n "$crystal_packages" ]; then
            echo "Found packages to remove: $crystal_packages"
            for pkg in $crystal_packages; do
                echo "Removing package: $pkg"
                sudo dpkg --remove --force-all $pkg || sudo apt-get remove -y --purge $pkg || true
            done
        fi
        
        # Also clean up any leftover files
        sudo rm -f /usr/bin/crystal /usr/bin/shards
    fi
    
    # Clean up previous Crystal installation directories if any
    for dir in /opt/crystal-*; do
        if [ -d "$dir" ]; then
            echo "Removing Crystal installation at $dir..."
            sudo rm -rf "$dir"
        fi
    done
    
    # Clean apt cache to avoid using cached packages
    sudo apt-get clean
    
    # Detect package manager
    if command_exists apt; then
        # Debian/Ubuntu based
        # First add the repository if needed
        if [ ! -f /etc/apt/sources.list.d/crystal.list ]; then
            echo "Adding Crystal repository..."
            curl -fsSL https://crystal-lang.org/install.sh | sudo bash || true
        fi
        
        # Try to install directly with apt
        echo "Installing Crystal with apt..."
        sudo apt-get update
        sudo apt-get install -y --allow-downgrades --reinstall crystal || {
            echo "WARNING: Standard Crystal installation failed, trying with --force-overwrite..."
            sudo apt-get install -y --allow-downgrades --reinstall --force-overwrite crystal || {
                echo "WARNING: Still failing, trying direct dpkg method..."
                sudo apt-get download crystal
                sudo dpkg -i --force-overwrite crystal*.deb
                sudo apt-get install -f -y
            }
        }
    elif command_exists dnf; then
        # Fedora/RHEL based
        curl -fsSL https://crystal-lang.org/install.sh | sudo bash
    elif command_exists pacman; then
        # Arch based
        sudo pacman -S crystal --noconfirm
    else
        echo "ERROR: Unsupported package manager. Please install Crystal manually."
        return 1
    fi

    # Verify installation
    if command_exists crystal; then
        installed_version=$(crystal --version | grep Crystal | awk '{print $2}')
        echo "Crystal $installed_version has been installed successfully."
    else
        echo "ERROR: Crystal installation failed."
        return 1
    fi
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
    
    # Build Moltiverse with release flag
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

# Function to ensure protocol files are in place
setup_protocol_files() {
    echo "Setting up protocol files environment..."
    
    # Set the MOLTIVERSE_PROTOCOL_PATH environment variable
    if ! grep -q "MOLTIVERSE_PROTOCOL_PATH" $HOME/.bashrc; then
        echo 'export MOLTIVERSE_PROTOCOL_PATH="$HOME/moltiverse/data"' >> $HOME/.bashrc
    fi
    
    echo "Protocol files setup complete."
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
    setup_protocol_files

    echo " "
    echo "=========================================================================="
    echo "Moltiverse has been successfully installed!"
    echo "Please restart your terminal or run 'source ~/.bashrc' to use Moltiverse."
    echo "The environment variable MOLTIVERSE_PROTOCOL_PATH has been set to point to"
    echo "the protocol files directory at $HOME/moltiverse/data"
}

main
