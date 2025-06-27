Tunneling Server A to C via reverse ssh on server B
```shell
wget https://raw.githubusercontent.com/Argo160/ssh-tunnel/main/NodeMarz.sh -O ssh-tunnel && chmod +x ssh-tunnel && bash ssh-tunnel
```
Features:

✅ Automatic SSH key setup - Sets up passwordless authentication /n
✅ Persistent monitoring - Checks connection every 30 seconds 
✅ Auto-restart - Restarts tunnel if it fails 
✅ Boot persistence - Automatically starts after reboot 
✅ Comprehensive logging - All activities logged to /var/log/ssh-tunnel.log 
✅ Easy management - Use tunnel-manager command for control


Management Commands:

tunnel-manager start      # Start the service
tunnel-manager stop       # Stop the service  
tunnel-manager restart    # Restart the service
tunnel-manager status     # Check status
tunnel-manager logs       # View logs
tunnel-manager logs -f    # Follow logs real-time
