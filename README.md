# tinker9-dockerfile
This dockerfile used to work to install tinker9 in a cuda10.1 compatible runtime container. Working to adapt it to changes in the tinker9 installation code/cmake so that it will continue to work in the future. 

To use, call like
```
docker build -f dockerfile -t mydockerhubprofile/tinker9:1.0.1-10.1-r .
```

