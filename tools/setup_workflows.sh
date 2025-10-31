#!/bin/bash

# CARB PEcAn Environment Setup Script
# This script automates the setup process described in CARB-Slurm-Pecan.md
# with defensive checking for all required components.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration variables
WORKFLOWS_REPO="https://github.com/ccmmf/workflows.git"
S3_ENDPOINT="https://s3.garage.ccmmf.ncsa.cloud"
S3_BUCKET="carb"
CONDA_ENV_NAME="PEcAn-head"
WORKFLOW_DIR="workflows/1a_single_site/slurm_distributed_workflow"
INPUT_DATA_FILE="00_cccmmf_phase_1a_input_artifacts.tgz"
EXPECTED_MD5="a3822874c7dd78cbb2de1be2aca76be3"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a file exists
file_exists() {
    [[ -f "$1" ]]
}

# Function to check if a directory exists
dir_exists() {
    [[ -d "$1" ]]
}

# Function to validate AWS credentials
check_aws_credentials() {
    log_info "Checking AWS credentials..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        log_info "Installation instructions: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws configure list | grep -q "access_key"; then
        log_warning "AWS credentials not configured. You will need to configure them."
        log_info "Run: aws configure"
        log_info "Use these values:"
        log_info "  AWS Access Key ID: GK8bb0d9c6b355c9a25b0b67fa"
        log_info "  AWS Secret Access Key: [provided separately]"
        log_info "  Default region name: garage"
        log_info "  Default output format: [leave blank]"
        
        read -p "Have you configured AWS credentials? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Please configure AWS credentials first and run this script again."
            exit 1
        fi
    fi
    
    # Test S3 access
    log_info "Testing S3 access..."
    if ! aws s3 ls --endpoint-url "$S3_ENDPOINT" "s3://$S3_BUCKET" >/dev/null 2>&1; then
        log_error "Cannot access S3 bucket. Please check your credentials and network connection."
        exit 1
    fi
    
    log_success "AWS credentials and S3 access verified"
}

# Function to check and install conda if needed
check_conda() {
    log_info "Checking Conda installation..."
    
    if command_exists conda; then
        log_success "Conda is already installed"
        return 0
    fi
    
    log_warning "Conda is not installed. Installing Miniconda..."
    
    # Download and install Miniconda
    local miniconda_installer="Miniconda3-latest-Linux-x86_64.sh"
    
    if ! file_exists "$miniconda_installer"; then
        log_info "Downloading Miniconda installer..."
        wget -q "https://repo.anaconda.com/miniconda/$miniconda_installer"
    fi
    
    log_info "Installing Miniconda..."
    bash "$miniconda_installer" -b -p "$HOME/miniconda3"
    
    # Add conda to PATH
    export PATH="$HOME/miniconda3/bin:$PATH"
    echo 'export PATH="$HOME/miniconda3/bin:$PATH"' >> "$HOME/.bashrc"
    
    # Initialize conda
    "$HOME/miniconda3/bin/conda" init bash
    
    log_success "Miniconda installed successfully"
    log_warning "Please restart your shell or run 'source ~/.bashrc' to use conda"
}

# Function to check required software modules
check_software_modules() {
    log_info "Checking required software modules..."
    
    # Check for module command
    if ! command_exists module; then
        log_error "Environment Modules system is not available."
        log_error "Please ensure the Environment Modules system is installed on this HPC cluster."
        exit 1
    fi
    
    # Check for apptainer module by attempting to load it
    log_info "Checking for apptainer module..."
    if module load apptainer 2>/dev/null; then
        log_success "Apptainer module loaded successfully"
        # Unload it for now - we'll load it again when needed
        module unload apptainer
    else
        log_error "Failed to load apptainer module."
        log_error "Please contact your system administrator to make the apptainer module available."
        exit 1
    fi
    
    log_success "Required software modules are available"
}

# Function to setup conda environment
setup_conda_environment() {
    log_info "Setting up Conda environment..."
    
    # Ensure conda is in PATH
    if ! command_exists conda; then
        if [[ -f "$HOME/miniconda3/bin/conda" ]]; then
            export PATH="$HOME/miniconda3/bin:$PATH"
        else
            log_error "Conda is not available. Please install it first."
            exit 1
        fi
    fi
    
    # Create conda directories if they don't exist
    mkdir -p "$HOME/.conda/envs"
    
    # Check if environment already exists
    if conda env list | grep -q "$CONDA_ENV_NAME"; then
        log_warning "Conda environment '$CONDA_ENV_NAME' already exists."
        read -p "Do you want to recreate it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing environment..."
            conda env remove -n "$CONDA_ENV_NAME" -y
        else
            log_info "Using existing environment..."
            return 0
        fi
    fi
    
    # Download and extract the environment tarball
    local env_tarball="PEcAn-head.tar.gz"
    
    if ! file_exists "$env_tarball"; then
        log_info "Downloading PEcAn environment tarball..."
        aws s3 cp --endpoint-url "$S3_ENDPOINT" \
            "s3://$S3_BUCKET/environments/PEcAn-head.tar.gz" "./$env_tarball"
    fi
    
    # Create environment directory
    mkdir -p "$HOME/.conda/envs/$CONDA_ENV_NAME"
    
    # Extract the tarball
    log_info "Extracting environment tarball..."
    tar -xzf "$env_tarball" -C "$HOME/.conda/envs/$CONDA_ENV_NAME"
    
    # Configure environment paths using conda run
    log_info "Configuring environment paths..."
    
    if conda run -n "$CONDA_ENV_NAME" conda-unpack; then
        log_success "conda-unpack completed successfully"
    else
        log_warning "conda-unpack failed or not found. Environment may need manual path configuration."
    fi
    
    # Verify R installation
    log_info "Verifying R installation..."
    if conda run -n "$CONDA_ENV_NAME" Rscript -e '.libPaths()' >/dev/null 2>&1; then
        log_success "R installation verified"
    else
        log_error "R installation verification failed"
        exit 1
    fi
    
    # Verify PEcAn libraries
    log_info "Verifying PEcAn libraries..."
    if conda run -n "$CONDA_ENV_NAME" Rscript -e 'library("PEcAn.workflow")' >/dev/null 2>&1; then
        log_success "PEcAn.workflow library verified"
    else
        log_error "PEcAn.workflow library not available"
        exit 1
    fi
    
    if conda run -n "$CONDA_ENV_NAME" Rscript -e 'library("PEcAn.remote")' >/dev/null 2>&1; then
        log_success "PEcAn.remote library verified"
    else
        log_error "PEcAn.remote library not available"
        exit 1
    fi
    
    log_success "Conda environment setup completed"
}

# Function to clone workflows repository
clone_workflows() {
    log_info "Cloning workflows repository..."
    
    if dir_exists "workflows"; then
        log_warning "Workflows directory already exists."
        read -p "Do you want to remove and re-clone? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf workflows
        else
            log_info "Using existing workflows directory..."
            return 0
        fi
    fi
    
    git clone "$WORKFLOWS_REPO"
    
    if [[ ! -d "$WORKFLOW_DIR" ]]; then
        log_error "Expected workflow directory not found: $WORKFLOW_DIR"
        exit 1
    fi
    
    log_success "Workflows repository cloned successfully"
}

# Function to download and setup workflow data
setup_workflow_data() {
    log_info "Setting up workflow data..."
    
    cd "$WORKFLOW_DIR"
    
    # Download input data
    if ! file_exists "$INPUT_DATA_FILE"; then
        log_info "Downloading workflow input data..."
        aws s3 cp --endpoint-url "$S3_ENDPOINT" \
            "s3://$S3_BUCKET/data/workflows/phase_1a/$INPUT_DATA_FILE" "./$INPUT_DATA_FILE"
    fi
    
    # Verify download
    log_info "Verifying data integrity..."
    local actual_md5
    actual_md5=$(md5sum "$INPUT_DATA_FILE" | cut -d' ' -f1)
    
    if [[ "$actual_md5" != "$EXPECTED_MD5" ]]; then
        log_error "MD5 checksum mismatch!"
        log_error "Expected: $EXPECTED_MD5"
        log_error "Actual: $actual_md5"
        exit 1
    fi
    
    log_success "Data integrity verified"
    
    # Extract data
    log_info "Extracting workflow data..."
    tar -xf "$INPUT_DATA_FILE"
    
    log_success "Workflow data setup completed"
}

# Function to setup apptainer
setup_apptainer() {
    log_info "Setting up Apptainer..."
    
    # Load apptainer module
    module load apptainer
    
    # Verify apptainer is available
    if ! command_exists apptainer; then
        log_error "Apptainer is not available after loading module"
        exit 1
    fi
    
    # Pull the required Docker image
    local sif_file="model-sipnet-git_latest.sif"
    
    if ! file_exists "$sif_file"; then
        log_info "Pulling PEcAn SIPNET model container..."
        apptainer pull docker://pecan/model-sipnet-git:latest
    else
        log_info "Apptainer image already exists: $sif_file"
    fi
    
    log_success "Apptainer setup completed"
}

# Function to create activation script
create_activation_script() {
    log_info "Creating environment activation script..."
    
    cat > "activate_carb_pecan.sh" << 'EOF'
#!/bin/bash
# CARB PEcAn Environment Activation Script

# Load required modules
module load apptainer

# Activate conda environment
source ~/.conda/envs/PEcAn-head/bin/activate

echo "CARB PEcAn environment activated!"
echo "Available commands:"
echo "  - conda activate PEcAn-head (if not already active)"
echo "  - module load apptainer (if not already loaded)"
echo "  - sbatch commands for running workflows"
EOF
    
    chmod +x "activate_carb_pecan.sh"
    
    log_success "Activation script created: activate_carb_pecan.sh"
}

# Function to display final instructions
display_final_instructions() {
    log_success "Setup completed successfully!"
    echo
    log_info "Next steps:"
    echo "1. Activate the environment:"
    echo "   source activate_carb_pecan.sh"
    echo
    echo "2. Navigate to the workflow directory:"
    echo "   cd $WORKFLOW_DIR"
    echo
    echo "3. Run the workflow setup step:"
    echo "   sbatch -n1 --mem-per-cpu=1G --time=01:00:00 \\"
    echo "     --output=pecan_workflow_runlog_\"\$(date +%Y%m%d%H%M%S)_%j.log\" \\"
    echo "     apptainer run model-sipnet-git_latest.sif ./04a_run_model.R \\"
    echo "     --settings=slurm_distributed_single_site_almond.xml"
    echo
    echo "4. Run the main workflow:"
    echo "   sbatch -n1 --mem-per-cpu=1G --time=01:00:00 \\"
    echo "     --output=pecan_workflow_runlog_\"\$(date +%Y%m%d%H%M%S)_%j.log\" \\"
    echo "     ./04b_run_model.R \\"
    echo "     --settings=slurm_distributed_single_site_almond.xml"
    echo
    log_info "For more information, see: CARB-Slurm-Pecan.md"
}

# Main execution
main() {
    log_info "Starting CARB PEcAn environment setup..."
    echo
    
    # Check prerequisites
    check_aws_credentials
    check_conda
    check_software_modules
    
    # Setup environment
    setup_conda_environment
    clone_workflows
    setup_workflow_data
    setup_apptainer
    create_activation_script
    
    # Return to original directory
    cd - >/dev/null
    
    display_final_instructions
}

# Run main function
main "$@"
