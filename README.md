# Deblur CUDA

## Usage
```bash
# deblur w/ CUDA
$ make
$ ./deblur img/blurry.png img/orig.png 6 img/output6.png

# deblur w/ CPU
$ make cpu_deblur
$ ./cpu_deblur.out img/blurry.png img/orig.png 6 cpu-output6.png
```