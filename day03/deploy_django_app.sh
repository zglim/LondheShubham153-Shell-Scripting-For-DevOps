#!/bin/bash

# Deploy a Django app and handle errors

# Project directory name
PROJECT_DIR="django-notes-app"

# Files that must exist for the directory to be considered deployable
REQUIRED_FILES=("Dockerfile" "docker-compose.yml")

# Function to clone the Django app code
# Returns 0 on success (clone succeeded or directory already valid), 1 on failure.
# After this function returns 0, the caller is expected to cd into $PROJECT_DIR.
code_clone() {
    echo "Cloning the Django app..."
    if [ -d "$PROJECT_DIR" ]; then
        echo "The code directory already exists. Validating..."
        # Validate that the existing directory is actually a deployable project
        for f in "${REQUIRED_FILES[@]}"; do
            if [ ! -f "$PROJECT_DIR/$f" ]; then
                echo "ERROR: Directory '$PROJECT_DIR' exists but is missing required file '$f'." >&2
                echo "Please remove the directory and retry, or fix it manually." >&2
                return 1
            fi
        done
        echo "Directory '$PROJECT_DIR' is valid. Skipping clone."
    else
        git clone https://github.com/LondheShubham153/django-notes-app.git || {
            echo "Failed to clone the code." >&2
            return 1
        }
        # Verify clone produced the expected directory
        if [ ! -d "$PROJECT_DIR" ]; then
            echo "ERROR: Clone completed but directory '$PROJECT_DIR' was not created." >&2
            return 1
        fi
    fi
    return 0
}

# Function to enter the project directory.
# This is the single, stable entry point for directory switching.
enter_project_dir() {
    if ! cd "$PROJECT_DIR"; then
        echo "ERROR: Failed to enter project directory '$PROJECT_DIR'." >&2
        return 1
    fi
    # Final safety check: ensure we are in a directory with required files
    for f in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$f" ]; then
            echo "ERROR: After entering '$PROJECT_DIR', required file '$f' is missing." >&2
            return 1
        fi
    done
    echo "Entered project directory: $(pwd)"
    return 0
}

# Function to install required dependencies
install_requirements() {
    echo "Installing dependencies..."
    sudo apt-get update && sudo apt-get install -y docker.io nginx docker-compose || {
        echo "Failed to install dependencies." >&2
        return 1
    }
}

# Function to perform required restarts
required_restarts() {
    echo "Performing required restarts..."
    sudo chown "$USER" /var/run/docker.sock || {
        echo "Failed to change ownership of docker.sock." >&2
        return 1
    }

    # Uncomment the following lines if needed:
    # sudo systemctl enable docker
    # sudo systemctl enable nginx
    # sudo systemctl restart docker
}

# Function to deploy the Django app
# Must be called AFTER enter_project_dir().
deploy() {
    echo "Building and deploying the Django app..."

    # Guard: ensure we are in a directory that looks deployable
    if [ ! -f "Dockerfile" ] || [ ! -f "docker-compose.yml" ]; then
        echo "ERROR: deploy() called in '$(pwd)' which is missing Dockerfile or docker-compose.yml." >&2
        echo "Refusing to run docker build in the wrong directory." >&2
        return 1
    fi

    docker build -t notes-app . && docker-compose up -d || {
        echo "Failed to build and deploy the app." >&2
        return 1
    }
}

# Main deployment script
echo "********** DEPLOYMENT STARTED *********"

# 1. Clone (or validate existing) code
if ! code_clone; then
    echo "Code clone/validation failed. Aborting deployment." >&2
    exit 1
fi

# 2. Enter project directory (single entry point for cd)
if ! enter_project_dir; then
    echo "Failed to enter project directory. Aborting deployment." >&2
    exit 1
fi

# 3. Install dependencies
if ! install_requirements; then
    exit 1
fi

# 4. Perform required restarts
if ! required_restarts; then
    exit 1
fi

# 5. Deploy the app
if ! deploy; then
    echo "Deployment failed. Mailing the admin..."
    # Add your sendmail or notification logic here
    exit 1
fi

echo "********** DEPLOYMENT DONE *********"
