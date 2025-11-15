#!/bin/bash



set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

get_pool_info() {
    pool_name="rpool"
    
    log_info "Checking ZFS pool status..."
    
    if ! zpool list "$pool_name" >/dev/null 2>&1; then
        log_error "ZFS pool '$pool_name' does not exist"
        exit 1
    fi
    
    log_info "Showing full pool status information:"
    echo "----------------------------------------"
    zpool status "$pool_name"
    echo "----------------------------------------"
    
    log_info "Attempting to detect pool device..."
    
    POOL_DEVICE=$(zpool status "$pool_name" | grep -E "^\s+c[0-9]+t[0-9]+d[0-9]+" | awk '{print $1}' | head -1)
    
    if [[ -z "$POOL_DEVICE" ]]; then
        POOL_DEVICE=$(zpool status "$pool_name" | grep -E "^\s+c[0-9]+d[0-9]+" | awk '{print $1}' | head -1)
    fi
    
    if [[ -z "$POOL_DEVICE" ]]; then
        POOL_DEVICE=$(zpool status "$pool_name" | grep -E "^\s+c[0-9]+" | awk '{print $1}' | head -1)
    fi
    
    if [[ -z "$POOL_DEVICE" ]]; then
        POOL_DEVICE=$(zpool status "$pool_name" | grep "ONLINE" | grep -v "pool:" | grep -v "rpool" | awk '{print $1}' | head -1)
    fi
    
    if [[ -z "$POOL_DEVICE" ]]; then
        log_error "Unable to detect pool device automatically. Please specify manually."
        log_info "Available devices:"
        zpool status "$pool_name" | grep -E "^\s+[a-zA-Z0-9]+" | awk '{print $1}'
        
        echo ""
        echo "Please choose a device from the list above or press Ctrl+C to exit"
        read -p "Enter device name: " POOL_DEVICE
        
        if [[ -z "$POOL_DEVICE" ]]; then
            log_error "Device name cannot be empty"
            exit 1
        fi
    fi
    
    log_success "Detected pool device: $POOL_DEVICE"
}

show_before_status() {
    log_info "=== Status Before Expansion ==="
    echo "ZFS pool info:"
    zpool list rpool 2>/dev/null || echo "Unable to get pool list"
    echo ""
    echo "Disk usage:"
    df -h / 2>/dev/null || echo "Unable to get disk usage"
    echo ""
}

rescan_devices() {
    log_info "Rescanning storage devices..."
    
    devfsadm -Cv >/dev/null 2>&1 || log_warning "Device rescan may not be fully successful"
    
    sleep 3
    
    log_success "Device rescan complete"
}

expand_pool() {
    pool_name="rpool"
    
    log_info "Enabling ZFS autoexpand feature..."
    
    if zpool set autoexpand=on "$pool_name" 2>/dev/null; then
        log_success "Autoexpand feature enabled"
    else
        log_warning "Failed to enable autoexpand feature, trying manual expansion"
    fi
    
    log_info "Starting ZFS pool expansion..."
    
    BEFORE_SIZE=$(zpool list -H -o size "$pool_name" 2>/dev/null || echo "unknown")
    log_info "Pool size before expansion: $BEFORE_SIZE"
    
    log_info "Executing pool expansion command: zpool online -e $pool_name $POOL_DEVICE"
    
    if zpool online -e "$pool_name" "$POOL_DEVICE" 2>/dev/null; then
        log_success "Pool expansion command executed successfully"
    else
        log_warning "Pool expansion command may have failed, showing detailed output..."
        
        echo "Trying: zpool online -e $pool_name $POOL_DEVICE"
        zpool online -e "$pool_name" "$POOL_DEVICE" 2>&1 || true
    fi
    
    sleep 5
    
    AFTER_SIZE=$(zpool list -H -o size "$pool_name" 2>/dev/null || echo "unknown")
    log_info "Pool size after expansion: $AFTER_SIZE"
    
    if [[ "$BEFORE_SIZE" != "$AFTER_SIZE" && "$AFTER_SIZE" != "unknown" ]]; then
        log_success "Pool size expanded from $BEFORE_SIZE to $AFTER_SIZE"
    else
        log_info "Pool size change: $BEFORE_SIZE -> $AFTER_SIZE"
    fi
}

upgrade_pool() {
    pool_name="rpool"
    
    log_info "Checking if ZFS pool feature upgrade is required..."
    
    if zpool status "$pool_name" | grep -q "zpool upgrade"; then
        log_info "Upgrading ZFS pool features..."
        
        if echo "y" | zpool upgrade "$pool_name" >/dev/null 2>&1; then
            log_success "ZFS pool feature upgrade completed"
        else
            log_warning "ZFS pool feature upgrade failed, but expansion is not affected"
        fi
    else
        log_info "ZFS pool features are up to date, no upgrade needed"
    fi
}

show_after_status() {
    log_info "=== Status After Expansion ==="
    echo "ZFS pool info:"
    zpool list rpool 2>/dev/null || echo "Unable to get pool list"
    echo ""
    echo "Pool detailed status:"
    zpool status rpool 2>/dev/null || echo "Unable to get pool status"
    echo ""
    echo "Disk usage:"
    df -h / 2>/dev/null || echo "Unable to get disk usage"
    echo ""
}

verify_expansion() {
    log_info "Verifying expansion result..."
    
    if zpool status rpool 2>/dev/null | grep -q "ONLINE"; then
        log_success "ZFS pool status is OK"
    else
        log_error "ZFS pool status error"
        return 1
    fi
    
    if zpool status rpool 2>/dev/null | grep -q "No known data errors"; then
        log_success "No data errors detected"
    else
        log_warning "Please inspect data status"
    fi
    
    log_success "Expansion verification complete"
}


#auto extend disk
check_root

get_pool_info

show_before_status

rescan_devices

expand_pool

upgrade_pool

show_after_status

verify_expansion

echo ""
log_success "ZFS pool expansion script completed!"
echo "========================================"











echo '=================== start ===='


svcadm disable application/desktop-cache/input-method-cache:default


echo "openindiana" > /etc/nodename
svcadm restart system/identity:node

e1000g0=$(dladm show-link | grep up | head -1 | cut -d ' ' -f 1)
echo "e1000g0=$e1000g0"


cat > /etc/init.d/enable-$e1000g0 << 'EOF'
#!/bin/sh
# Auto-enable e1000g0 interface at boot

case "$1" in
start)
    /usr/sbin/ifconfig e1000g0 plumb up 2>/dev/null
    /usr/sbin/ifconfig e1000g0 dhcp start 2>/dev/null
    ;;
stop)
    ;;
*)
    echo "Usage: $0 {start|stop}"
    exit 1
    ;;
esac
exit 0
EOF

chmod +x /etc/init.d/enable-$e1000g0

ln -s /etc/init.d/enable-$e1000g0 /etc/rc3.d/S99enable-$e1000g0


bootadm set-menu timeout=1











