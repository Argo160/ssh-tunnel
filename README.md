Tunneling Server A to C via reverse ssh on server B
```shell
wget https://raw.githubusercontent.com/Argo160/ssh-tunnel/main/NodeMarz.sh -O ssh-tunnel && chmod +x ssh-tunnel && bash ssh-tunnel
```
Features:

✅ Automatic SSH key setup - Sets up passwordless authentication <br>
✅ Persistent monitoring - Checks connection every 30 seconds <br>
✅ Auto-restart - Restarts tunnel if it fails <br>
✅ Boot persistence - Automatically starts after reboot <br>
✅ Comprehensive logging - All activities logged to /var/log/ssh-tunnel.log <br>
✅ Easy management - Use tunnel-manager command for control<br>


Management Commands:

tunnel-manager start      # Start the service <br>
tunnel-manager stop       # Stop the service  <br>
tunnel-manager restart    # Restart the service <br>
tunnel-manager status     # Check status <br>
tunnel-manager logs       # View logs <br>
tunnel-manager logs -f    # Follow logs real-time <br>
