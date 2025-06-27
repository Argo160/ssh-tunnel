#!/bin/bash

# SSH Tunnel Manager Script
# This script creates and manages a persistent SSH reverse tunnel

SCRIPT_NAME="ssh-tunnel-manager"
SERVICE_NAME="ssh-tunnel"
SCRIPT_DIR="/opt/ssh-tunnel"
CONFIG_FILE="$SCRIPT_DIR/tunnel.conf"
LOG_FILE="/var/log/ssh-tunnel.log"
PID_FILE="/var/run/ssh-tunnel.pid"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Success message
success_msg() {
    echo -e "${GREEN}$1${NC}"
}

# Warning message
warning_msg() {
    echo -e "${YELLOW}$1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
}

# Create necessary directories
setup_directories() {
    mkdir -p "$SCRIPT_DIR"
    touch "$LOG_FILE"
    chmod 755 "$SCRIPT_DIR"
    chmod 644 "$LOG_FILE"
}

# Get server details from user
get_server_details() {
    echo "=== SSH Tunnel Configuration ==="
    echo

    read -p "Enter Server A IP address (destination server): " SERVER_A_IP
    read -p "Enter Server C IP address (target server): " SERVER_C_IP
    read -p "Enter username for Server A (default: root): " SERVER_A_USER
    SERVER_A_USER=${SERVER_A_USER:-root}

    # Validate IP addresses
    if ! [[ $SERVER_A_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error_exit "Invalid IP address for Server A"
    fi

    if ! [[ $SERVER_C_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error_exit "Invalid IP address for Server C"
    fi

    # Save configuration
    cat > "$CONFIG_FILE" << EOF
SERVER_A_IP=$SERVER_A_IP
SERVER_C_IP=$SERVER_C_IP
SERVER_A_USER=$SERVER_A_USER
EOF

    success_msg "Configuration saved to $CONFIG_FILE"
}

# Setup SSH key authentication
setup_ssh_key() {
    local ssh_dir="/root/.ssh"
    local key_file="$ssh_dir/id_rsa"

    # Create .ssh directory if it doesn't exist
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Generate SSH key if it doesn't exist
    if [[ ! -f "$key_file" ]]; then
        log "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N "" -C "ssh-tunnel@$(hostname)"
        success_msg "SSH key pair generated"
    fi

    # Copy public key to Server A
    echo
    warning_msg "Setting up SSH key authentication with Server A..."
    echo "You will be prompted for the password of $SERVER_A_USER@$SERVER_A_IP"

    if ssh-copy-id -i "$key_file.pub" "$SERVER_A_USER@$SERVER_A_IP"; then
        success_msg "SSH key successfully copied to Server A"
    else
        error_exit "Failed to copy SSH key to Server A"
    fi

    # Test SSH connection
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SERVER_A_USER@$SERVER_A_IP" "echo 'SSH key authentication successful'"; then
        success_msg "SSH key authentication test successful"
    else
        error_exit "SSH key authentication test failed"
    fi
}

# Create the tunnel monitoring daemon
create_tunnel_daemon() {
    cat > "$SCRIPT_DIR/tunnel-daemon.sh" << 'EOF'
#!/bin/bash

# Load configuration
SCRIPT_DIR="/opt/ssh-tunnel"
CONFIG_FILE="$SCRIPT_DIR/tunnel.conf"
LOG_FILE="/var/log/ssh-tunnel.log"
PID_FILE="/var/run/ssh-tunnel.pid"

# Source configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Configuration file not found" >> "$LOG_FILE"
    exit 1
fi

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to start SSH tunnel
start_tunnel() {
    log "Starting SSH tunnel: $SERVER_A_USER@$SERVER_A_IP -> $SERVER_C_IP:443"

    # Kill any existing tunnel processes
    pkill -f "ssh -N -R 443:$SERVER_C_IP:443"
    sleep 2

    # Start new tunnel in background
    ssh -N -R 443:$SERVER_C_IP:443 \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        $SERVER_A_USER@$SERVER_A_IP &

    SSH_PID=$!
    echo $SSH_PID > "$PID_FILE"
    log "SSH tunnel started with PID: $SSH_PID"
}

# Function to check if tunnel is alive
is_tunnel_alive() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            # Additional check: verify the process is actually our SSH tunnel
            if ps -p "$pid" -o cmd= | grep -q "ssh -N -R 443:$SERVER_C_IP:443"; then
                return 0
            fi
        fi
    fi
    return 1
}

# Main monitoring loop
main() {
    log "SSH tunnel daemon started"

    while true; do
        if ! is_tunnel_alive; then
            log "SSH tunnel is down, restarting..."
            start_tunnel
        else
            # Optional: Test actual connectivity
            if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SERVER_A_USER@$SERVER_A_IP" "echo 'Connection test'" >/dev/null 2>&1; then
                log "SSH connection test failed, restarting tunnel..."
                start_tunnel
            fi
        fi

        sleep 30  # Check every 30 seconds
    done
}

# Handle signals
cleanup() {
    log "Received termination signal, cleaning up..."
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null
        rm -f "$PID_FILE"
    fi
    pkill -f "ssh -N -R 443:$SERVER_C_IP:443"
    log "SSH tunnel daemon stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start the main function
main
EOF

    chmod +x "$SCRIPT_DIR/tunnel-daemon.sh"
    success_msg "Tunnel daemon script created"
}

# Create systemd service
create_systemd_service() {
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=SSH Reverse Tunnel Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$SCRIPT_DIR/tunnel-daemon.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    success_msg "Systemd service created"
}

# Create management script
create_management_script() {
    cat > "$SCRIPT_DIR/manage-tunnel.sh" << 'EOF'
#!/bin/bash

SERVICE_NAME="ssh-tunnel"
LOG_FILE="/var/log/ssh-tunnel.log"

case "$1" in
    start)
        echo "Starting SSH tunnel service..."
        systemctl start $SERVICE_NAME
        systemctl status $SERVICE_NAME
        ;;
    stop)
        echo "Stopping SSH tunnel service..."
        systemctl stop $SERVICE_NAME
        ;;
    restart)
        echo "Restarting SSH tunnel service..."
        systemctl restart $SERVICE_NAME
        systemctl status $SERVICE_NAME
        ;;
    status)
        systemctl status $SERVICE_NAME
        ;;
    logs)
        if [[ "$2" == "-f" ]]; then
            tail -f "$LOG_FILE"
        else
            tail -n 50 "$LOG_FILE"
        fi
        ;;
    enable)
        echo "Enabling SSH tunnel service to start on boot..."
        systemctl enable $SERVICE_NAME
        ;;
    disable)
        echo "Disabling SSH tunnel service..."
        systemctl disable $SERVICE_NAME
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|logs -f|enable|disable}"
        exit 1
        ;;
esac
EOF

    chmod +x "$SCRIPT_DIR/manage-tunnel.sh"
    ln -sf "$SCRIPT_DIR/manage-tunnel.sh" "/usr/local/bin/tunnel-manager"
    success_msg "Management script created (accessible via 'tunnel-manager' command)"
}

# Main installation function
main() {
    check_root

    echo "=== SSH Tunnel Manager Installation ==="
    echo

    setup_directories
    get_server_details

    # Load configuration for the setup process
    source "$CONFIG_FILE"

    setup_ssh_key
    create_tunnel_daemon
    create_systemd_service
    create_management_script

    # Enable and start the service
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    echo
    success_msg "=== Installation Complete ==="
    echo
    echo "SSH Tunnel Configuration:"
    echo "  Server A (destination): $SERVER_A_USER@$SERVER_A_IP"
    echo "  Server C (target): $SERVER_C_IP:443"
    echo "  Tunnel: 443:$SERVER_C_IP:443"
    echo
    echo "Service Management Commands:"
    echo "  tunnel-manager start     - Start the tunnel service"
    echo "  tunnel-manager stop      - Stop the tunnel service"
    echo "  tunnel-manager restart   - Restart the tunnel service"
    echo "  tunnel-manager status    - Check service status"
    echo "  tunnel-manager logs      - View recent logs"
    echo "  tunnel-manager logs -f   - Follow logs in real-time"
    echo
    echo "The service is now running and will automatically:"
    echo "  - Start on system boot"
    echo "  - Monitor the SSH connection every 30 seconds"
    echo "  - Restart the tunnel if it fails"
    echo "  - Log all activities to $LOG_FILE"
    echo
    warning_msg "Please test the tunnel connection from Server A using: nc -zv localhost 443"
}

# Run main function
main "$@"
