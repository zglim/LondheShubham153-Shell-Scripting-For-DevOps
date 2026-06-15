#!/bin/bash

# Deploy a Django app and handle errors

# Name of the repository directory that holds the Django project and Docker config.
REPO_DIR="django-notes-app"
REPO_URL="https://github.com/LondheShubham153/django-notes-app.git"

# Verify that a directory looks like a deployable Django + Docker project.
# Deployment runs `docker build -t notes-app .` and `docker-compose up -d`, so the
# directory must contain both a Dockerfile and a docker-compose file.
is_deployable_dir() {
    local dir="$1"
    [ -f "$dir/Dockerfile" ] || return 1
    [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/docker-compose.yaml" ] || return 1
    return 0
}

# Function to clone the Django app code and enter its directory.
#
# This is the single, stable entry point for switching into the project directory.
# On success the current working directory is the validated project root, so the
# rest of the deployment does not need to re-derive or re-assume the working dir.
# On any failure it returns non-zero WITHOUT changing the working directory, so the
# main flow stops instead of running later steps in the wrong place.
code_clone() {
    echo "Cloning the Django app..."

    if [ -d "$REPO_DIR" ]; then
        echo "The code directory already exists. Skipping clone."
    else
        git clone "$REPO_URL" || {
            echo "Failed to clone the code."
            return 1
        }
    fi

    # The directory must exist now (either pre-existing or freshly cloned).
    if [ ! -d "$REPO_DIR" ]; then
        echo "Expected directory '$REPO_DIR' is missing after clone."
        return 1
    fi

    # Guard against an existing-but-incomplete / non-deployable directory:
    # fail explicitly instead of skipping the clone and deploying a broken tree.
    if ! is_deployable_dir "$REPO_DIR"; then
        echo "Directory '$REPO_DIR' is not a deployable project (missing Dockerfile or docker-compose file)."
        return 1
    fi

    # Single place where we enter the project directory before any deploy step.
    cd "$REPO_DIR" || {
        echo "Failed to enter the project directory '$REPO_DIR'."
        return 1
    }

    echo "Working directory is now: $(pwd)"
}

# Function to install required dependencies
install_requirements() {
    echo "Installing dependencies..."
    sudo apt-get update && sudo apt-get install -y docker.io nginx docker-compose || {
        echo "Failed to install dependencies."
        return 1
    }
}

# Function to perform required restarts
required_restarts() {
    echo "Performing required restarts..."
    sudo chown "$USER" /var/run/docker.sock || {
        echo "Failed to change ownership of docker.sock."
        return 1
    }

    # Uncomment the following lines if needed:
    # sudo systemctl enable docker
    # sudo systemctl enable nginx
    # sudo systemctl restart docker
}

# Function to deploy the Django app.
#
# Deployment must run inside the project directory (the one with the Dockerfile and
# docker-compose config). The working directory is set once in code_clone(); here we
# only assert that precondition so a wrong cwd fails loudly instead of misreporting a
# Docker build/compose error.
deploy() {
    echo "Building and deploying the Django app..."

    if ! is_deployable_dir "."; then
        echo "Current directory '$(pwd)' is not a deployable project. Aborting deploy."
        return 1
    fi

    docker build -t notes-app . && docker-compose up -d || {
        echo "Failed to build and deploy the app."
        return 1
    }
}

# Main deployment flow.
main() {
    echo "********** DEPLOYMENT STARTED *********"

    # Clone the code and enter the project directory (single entry point for the cd).
    if ! code_clone; then
        echo "Aborting deployment: could not prepare the project directory."
        exit 1
    fi

    # Install dependencies
    if ! install_requirements; then
        exit 1
    fi

    # Perform required restarts
    if ! required_restarts; then
        exit 1
    fi

    # Deploy the app
    if ! deploy; then
        echo "Deployment failed. Mailing the admin..."
        # Add your sendmail or notification logic here
        exit 1
    fi

    echo "********** DEPLOYMENT DONE *********"
}

# Run the main flow only when executed directly, so the functions above can be
# sourced (e.g. by tests) without triggering an actual deployment.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
