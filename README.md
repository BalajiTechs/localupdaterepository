# localupdaterepository
### Script to create local update repositories for multiple linux distribution


#### Using the scripts

**There are three files** 

- setup-local-repo-ubuntu-centos-suse.bash
This script can be used to configure local repository for AmazonLinx2, RHEL-7, CentOS-7, Ubuntu-Xenail and SLES/OpenSUSE 12.
Script uses generate_updateinfo.py file internally so this must be in the same directory.

- genrate_updateinfo.py
Used internally by setup-local-repo-ubuntu-centos-suse.bash script

- enable_local_repo_updated.bash
Script to configure clients to get updates from local repo


#### Pre-Requisites
1. Ubuntu-Xenail server with internet access
2. 150 GB of available space


> Asumptions: the repo_base directory is /data/repo and is able to handle 150 GB data

#### Steps to configure repo server
1. copy setup-local-repo.bash and generate_updateinfo.py on ubuntu machine
2. switch to root and execute below commands
```
chmod +x setup-local-repo.bash
chmod +x generate_updateinfo.py
```

3. Update amzn2_repo_base_url parameter in setup-local-repo.bash script.
4. Execute below commands
```
./setup-local-repo.bash /data/repo
```
5. execute below commands
```
update_local_repo
```

> Note down the fqdn of server for future purpose

#### Client side(assuming the fqdn of repo server is repo-server.example.com)
On client side copy enable_local_repo_updated.bash file and execute below command as root
```
chmod +x enable_local_repo_updated.bash
./enable_local_repo_updated.bash repo-server.example.com
```
#### Thats It just check with the respective package manager for any updates from you own local repository
