/*
* Henry Son
* ECE453 - Advanced Computer Architecture
* Professor Billoo
* 
* Header file for GPU timing with cuda
*
* Reference(s):
* https://developer.nvidia.com/blog/how-implement-performance-metrics-cuda-cc/
*/

#ifndef __GPU_TIMING_H
#define __GPU_TIMING_H

#include <cuda.h>
#include <cuda_runtime.h>

class gpu_time {
    cudaEvent_t start, stop;

    /* constructor */
    gpu_time() {
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
    }

    /* destructor */
    ~gpu_time() {
        cudaEventDestroy(start);
        cudaEventDestroy(stop);
    }

    /* begin timer */
    void begin() {
        cudaEventRecord(start);
    }

    /* end timer */
    void end() {
        cudaEventRecord(stop);
    }

    /* total elapsed time in milliseconds */
    float elapsed_time() {
        float t = 0;
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&t, start, stop);
        return t;
    }
};

#endif