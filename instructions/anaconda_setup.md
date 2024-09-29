### Anaconda installation

#### make conda installer executable	
```
chmod +x Anaconda3-<version>-Linux-x86_64.sh
```
#### run the installer	
```
./Anaconda3-<version>-Linux-x86_64.sh
```
#### add conda to PATH
```
nano ~/.bashrc && export PATH="/path/to/anaconda3/bin:$PATH"
```
#### run bash file
```
source ~/.bashrc
```
#### create a python environment with the requirements file
- Create the Conda environment with Python 
    ```	
    conda create -n test_env python=3.9.11
    ```
- Activate the newly created environment
    ```	
    conda activate test_env
    ```
- Install the required packages from the requirements.txt file
    ```	
    python -m pip install -r requirements.txt
    ```
