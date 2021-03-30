/*
* Henry Son
* ECE453 - Advanced Computer Architecture
* Professor Billoo
* 
* Header file for GPU timing with cuda
*
* Reference(s):
* https://en.wikipedia.org/wiki/Richardson%E2%80%93Lucy_deconvolution
* https://github.com/imagej/ops-experiments/blob/master/ops-experiments-cuda/native/YacuDecu/src/deconv.cu
*/

#include <stdio.h> 
#include <cuda_runtime.h>
#include <helper_cuda.h>
#include <cuComplex.h>
#include <cuda_profiler_api.h>
#include <cufft.h>

#include <iostream>
#include <array>
#include <vector>

#include "../../dep/metrics/metrics.h"
#include "../../dep/lodepng/lodepng.h"

#define BLOCK_SIZE 32

using namespace std;

/* kernel functions for deconvolution */
__global__ void complexMul(cuComplex *A, cuComplex *B, cuComplex *C) {
    unsigned int i = blockIdx.x * gridDim.y * gridDim.z *
                     blockDim.x + blockIdx.y + gridDim.z *
                     blockDim.x + blockIdx.z * blockDim.x + threadIdx.x;

    C[i] = cuCmulf(A[i], B[i]);
}

__global__ void floatMul(float *A, float *B, float *C) {
    unsigned int i = blockIdx.x * gridDim.y * gridDim.z *
                     blockDim.x + blockIdx.y * gridDim.z *
                     blockDim.x + blockIdx.z * blockDim.x + threadIdx.x;

    C[i] = A[i] * B[i];
}

__global__ void floatDiv(float *A, float *B, float *C) {
    unsigned int i = blockIdx.x * gridDim.y * gridDim.z *
                     blockDim.x + blockIdx.y * gridDim.z *
                     blockDim.x + blockIdx.z * blockDim.x + threadIdx.x;

    if((int)B[i] == 0) {
        C[i] = A[i];
    } else {
        C[i] = A[i] / B[i];
    }
}

/* convolution for a 3-channel input 
* A = input matrix 1
* B = input matrix 2
* C = output matrix
* AH = height of matrix A
* AW = width of matrix A
* BH = height of matrix B
* BW = width of matrix B
*/
__global__ void convolution(float *A, float *B, float *C, int AH, int AW, int BH, int BW) {
    unsigned int i = blockIdx.x * gridDim.y * gridDim.z *
                     blockDim.x + blockIdx.y + gridDim.z *
                     blockDim.x + blockIdx.z * blockDim.x + threadIdx.x;
    
    int color = i / (AH * AW);
    int diff = (-BW / 2) + (AW * (-BH / 2));
    float sum = 0;

    if(i + diff > 0 && ((i + diff) / (AH * AW) == color) && ((i - diff) / (AH * AW) == color)) {
        for(int x = -BW / 2; x < BW / 2; x++) {
            for(int y = -BH / 2; y < BH / 2; y++) {
                sum += A[i + x + (AW * y)] * B[(x + (BH / 2)) + ((y + (BW / 2)) * BW)];
            }
        }
        C[i] = sum;
    }
}

static cudaError_t numBlocksThreads(unsigned int N, dim3 *numBlocks, dim3 *threadsPerBlock) {
    unsigned int BLOCKSIZE = 128;
    int Nx, Ny, Nz, device;
    cudaError_t err;

    if(N < BLOCKSIZE) {
        numBlocks->x = 1;
        numBlocks->y = 1;
        numBlocks->z = 1;

        threadsPerBlock->x = N;
        threadsPerBlock->y = 1;
        threadsPerBlock->z = 1;

        return cudaSuccess;
    }

    threadsPerBlock->x = BLOCKSIZE;
    threadsPerBlock->y = 1;
    threadsPerBlock->z = 1;

    err = cudaGetDevice(&device);
    if(err)
        return err;

    err = cudaDeviceGetAttribute(&Nx, cudaDevAttrMaxBlockDimX, device);
    if(err)
        return err;
    
    err = cudaDeviceGetAttribute(&Ny, cudaDevAttrMaxBlockDimY, device);
    if(err)
        return err;

    err = cudaDeviceGetAttribute(&Nz, cudaDevAttrMaxBlockDimZ, device);
    if(err)
        return err;

    unsigned int n = (N - 1) / BLOCKSIZE + 1;
    unsigned int x = (n - 1) / (Ny * Nz) + 1;
    unsigned int y = (n - 1) / (x * Nz) + 1;
    unsigned int z = (n - 1) / (x * y) + 1;

    if(x > Nx || y > Ny || z > Nz) {
        return cudaErrorInvalidConfiguration;
    }

    numBlocks->x = x;
    numBlocks->y = y;
    numBlocks->z = z;

    return cudaSuccess;
}

/* deconvolution using lucy-richardson algorithm
* nIter = number of interations
* n1 = size of dim 1 (im.x)
* n2 = size of dim 2 (im.y)
* n3 = size of dim 3 (im.channels) (3 for rgb)
* hImage = pointer to image memory
* hPSF = pointer to PSF memory
* hObject = pointer to output image memory
* psf_x = num rows in PSF
* psf_y = num cols in PSF
*/
float deconvLR(unsigned int nIter, size_t n1, size_t n2, size_t n3, float *hImage, float *hPSF, float *hObject, int psf_x, int psf_y, float *hPSF2) {
    cudaError_t err;

    float *img = 0;
    float *obj = 0;
    float *psf = 0;
    float *otf = 0;
    float *buf = 0;
    float *tmp = 0;
    float *tmp2 = 0;

    size_t nSpatial = n1 * n2 * n3;
    size_t mSpatial;
    dim3 spatialThreadsPerBlock, spatialBlocks;

    err = numBlocksThreads(nSpatial, &spatialBlocks, &spatialThreadsPerBlock);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    mSpatial = spatialBlocks.x * spatialBlocks.y * spatialBlocks.z * spatialThreadsPerBlock.x * sizeof(float);

    cudaDeviceReset();
    cudaProfilerStart();
  
    /* memory allocation */
    err = cudaMalloc(&img, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMalloc(&obj, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMalloc(&psf, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMalloc(&otf, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMalloc(&buf, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMalloc(&tmp, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMalloc(&tmp2, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMemset(img, 0, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMemset(obj, 0, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMemset(buf, 0, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMemset(tmp, 0, mSpatial);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    /* memory copy for gpu mem */
    err = cudaMemcpy(img, hImage, nSpatial*sizeof(float), cudaMemcpyHostToDevice);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMemcpy(psf, hPSF, nSpatial*sizeof(float), cudaMemcpyHostToDevice);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMemcpy(otf, hPSF2, nSpatial*sizeof(float), cudaMemcpyHostToDevice);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }

    err = cudaMemcpy(obj, hImage, nSpatial*sizeof(float), cudaMemcpyHostToDevice);
    if(err) {
        fprintf(stderr, "CUDA error: %d\n", err);
        return err;
    }
  
    /* timing */
    cudaEvent_t start, stop;
    cudaEventCreate(&start); 
    cudaEventCreate(&stop);
    cudaEventRecord(start, 0);

    for(int i = 0; i < nIter; i++) {
        convolution <<< spatialBlocks, spatialThreadsPerBlock >>> (obj, psf, tmp, n1, n2, psf_x, psf_y);
        floatDiv <<< spatialBlocks, spatialThreadsPerBlock >>> (img, tmp, buf);
        convolution <<< spatialBlocks, spatialThreadsPerBlock >>> (buf, otf, tmp, n1, n2, psf_x, psf_y);
        floatMul <<< spatialBlocks, spatialThreadsPerBlock >>> (tmp, obj, obj);
    }

    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);

    float t = 0;
    cudaEventElapsedTime(&t, start, stop);

    // copy output to host
    err = cudaMemcpy(hObject, obj, nSpatial*sizeof(float), cudaMemcpyDeviceToHost);
    if(err) {
        fprintf(stderr, "CUDA error in output: %d\n", err);
        return err;
    }

    // free memory
    if(img)
        cudaFree(img);
    if(obj)
        cudaFree(obj);
    if(otf)
        cudaFree(otf);
    if(buf)
        cudaFree(buf);
    if(tmp)
        cudaFree(tmp);

    cudaProfilerStop();
    cudaDeviceReset();

    return t;
}

/* Decode the PNG into a 1D vector */
std::vector<int> decodePNG(const char* filename, unsigned &w, unsigned &h) {
    std::vector<unsigned char> image;

    lodepng::decode(image, w, h, filename);

    std::vector<int> image_without_alpha;

    for(unsigned int i = 0; i < image.size(); i+=4){
        image_without_alpha.push_back((int)image[i]);
    }
    for(unsigned int i = 1; i < image.size(); i+=4){
        image_without_alpha.push_back((int)image[i]);
    }
    for(unsigned int i = 2; i < image.size(); i+=4){
        image_without_alpha.push_back((int)image[i]);
    }

    return image_without_alpha;
}

int encodePNG(vector<int> im, unsigned &w, unsigned &h, char *filename){
    vector<unsigned char> image;
    for(int i = 0; i < im.size()/3; i++){
        image.push_back(im[i]);
        image.push_back(im[i+(w*h)]);
        image.push_back(im[i+(2*w*h)]);
        image.push_back(255);
    }
    unsigned err = lodepng::encode((const char *)filename, image, w, h);
    return 0;
}

/* Copy contents of vector to arr to be used in CUDA kernel functions */
float * vecToArr(std::vector<int> image) {
    float *arr = (float *)malloc(image.size() * sizeof(float));
    if(!arr) {
        std::cerr << "Error converting vector to array" << std::endl;
        exit(-1);
    }

    std::copy(image.begin(), image.end(), arr);

    return arr;
}

const double pi = 3.14159265358979323846;

std::vector<std::vector<std::vector<double>>> calculatePSF(std::vector<std::vector<std::vector<double> > > &psf_hat, int size) {
	int psf_size = size;
	double mean_row = 0.0;
	double mean_col = 0.0;

	double sigma_row = 49.0;
	double sigma_col = 36.0;

	double sum = 0.0;
	double temp;

	std::vector<std::vector<double> > psf_init(psf_size, std::vector<double> (psf_size));
	std::vector<std::vector<std::vector<double> > > psf_final(psf_size, std::vector<std::vector<double> > (psf_size, std::vector<double> (3)));
	psf_hat.resize(psf_size, std::vector<std::vector<double> >(psf_size, std::vector<double>(3)));

	for (unsigned j = 0; j< psf_init.size(); j++) {
		for (unsigned k = 0; k< psf_init[0].size(); k++) {
			temp = exp(-0.5 * (pow((j - mean_row) / sigma_row, 2.0) + pow((k - mean_col) / sigma_col, 2.0))) / (2* pi * sigma_row * sigma_col);
			sum += temp;
			psf_init[j][k] = temp;
		}
	}

	for (unsigned row = 0; row<psf_init.size(); row++) {
		for (unsigned col = 0; col<psf_init[0].size(); col++) {
			psf_init[row][col] /= sum;
		}
	}

	for (unsigned row = 0; row<psf_init.size(); row++) {
		for (unsigned col = 0; col<psf_init[0].size(); col++) {
			double curr = psf_init[row][col];
			psf_final[row][col][0] = curr;
			psf_final[row][col][1] = curr;
			psf_final[row][col][2] = curr;
		}
	}
	for (int row = 0; row < psf_size; row++) {
		for (int col = 0; col < psf_size; col++) {
			int y = psf_size - 1 - row;
			int x = psf_size - 1 - col;
			psf_hat[y][x][0] = psf_final[row][col][0];
			psf_hat[y][x][1] = psf_final[row][col][1];
			psf_hat[y][x][2] = psf_final[row][col][2];
		}
	}
	cerr << psf_final[0][0][0] << endl;
	return psf_final;
}

void flip(float *hPSF, float *psfFLIP, int PSF_x, int PSF_y) {
  for(int i = 0; i < PSF_x; i++) {
        for(int j = 0; j < PSF_y; j++) {
            psfFLIP[(PSF_x*PSF_y) - j - (i*PSF_y) - 1 + 0*(PSF_x*PSF_y)] = hPSF[j + PSF_y*i + 0*(PSF_x*PSF_y)];
            psfFLIP[(PSF_x*PSF_y) - j - (i*PSF_y) - 1 + 1*(PSF_x*PSF_y)] = hPSF[j + PSF_y*i + 1*(PSF_x*PSF_y)];
            psfFLIP[(PSF_x*PSF_y) - j - (i*PSF_y) - 1 + 2*(PSF_x*PSF_y)] = hPSF[j + PSF_y*i + 2*(PSF_x*PSF_y)];
        }
  }
}

void convert1D(std::vector<std::vector<std::vector<double> > > &a, std::vector<double> &vec1D) {
	for(unsigned i = 0; i < a.size(); i++) {
		for(unsigned j = 0; j < a[0].size(); j++) {
			vec1D.push_back(a[i][j][0]);
			//vec1D.push_back(a[i][j][1]);
			//vec1D.push_back(a[i][j][2]);
			//vec1D.push_back((unsigned char)(255));
		}
	}
    for(unsigned i = 0; i < a.size(); i++) {
        for(unsigned j = 0; j < a[0].size(); j++) {
            //vec1D.push_back(a[i][j][0]);
            vec1D.push_back(a[i][j][1]);
            //vec1D.push_back(a[i][j][2]);
            //vec1D.push_back((unsigned char)(255));
        }
    }
    for(unsigned i = 0; i < a.size(); i++) {
        for(unsigned j = 0; j < a[0].size(); j++) {
            //vec1D.push_back(a[i][j][0]);
            //vec1D.push_back(a[i][j][1]);
            vec1D.push_back(a[i][j][2]);
            //vec1D.push_back((unsigned char)(255));
        }
    }

}


float * vecToArr2(std::vector<double> image) {
    float *arr = (float *)malloc(image.size() * sizeof(float));
    if(!arr) {
        std::cerr << "Error converting vector to array" << std::endl;
        exit(-1);
    }

    std::copy(image.begin(), image.end(), arr);

    return arr;
}

int main(int argc, char **argv) {
    if(argc != 5) {
        std::cerr << "Usage:  " << argv[0] << " blurry.png ref.png iterations out.png" << std::endl;
        exit(-1);
    }

    float ret = 0;
    int im_z = 3;

    int nIter = atoi(argv[3]);
    int PSF_x = 5;
    int PSF_y = 5;

    std::vector<std::vector<std::vector<double>>> psf_hat;
    std::vector<std::vector<std::vector<double>>> psf_vec = calculatePSF(psf_hat, PSF_x);
    std::vector<double> psf_1d;
    convert1D(psf_vec, psf_1d);
    float *PSF = vecToArr2(psf_1d);
    float *PSF2 = vecToArr2(psf_1d);
    flip(PSF, PSF2, 5, 5);

    /* convert the PNGs to 1D vectors */
    unsigned w_blurry, h_blurry;
    unsigned w_ref, h_ref;
    std::vector<int> blurry = decodePNG(argv[1], w_blurry, h_blurry);
    std::vector<int> ref = decodePNG(argv[2], w_ref, h_ref);

    /* convert image into array to be used in kernel functions */
    float *blurry_arr = vecToArr(blurry);
    float *out_arr = (float *)malloc(w_blurry * h_blurry * im_z *sizeof(float));

    /* call kernel function with blurry_arr, w_blurry, h_blurry */
    ret = deconvLR(nIter, h_blurry, w_blurry, im_z, blurry_arr, PSF, out_arr, PSF_x, PSF_y, PSF2);

    /* re-convert back to vector for metrics computation */
    std::vector<int> out_vec;
    for(int i = 0; i < (h_blurry * w_blurry * im_z); i++)
        out_vec.push_back( static_cast<int>(out_arr[i]) );

    /* metrics */
    std::cout << "Blurry MSE: " << _mse(blurry, w_blurry, h_blurry, ref) << std::endl;
    std::cout << "Blurry pSNR: " << psnr(blurry, w_blurry, h_blurry, ref) << std::endl;
    std::cout << "Deblur MSE: " << _mse(out_vec, w_blurry, h_blurry, ref) << std::endl;
    std::cout << "Deblur pSNR: " << psnr(out_vec, w_blurry, h_blurry, ref) << std::endl;
    std::cout << "Elapsed time (ms): " << ret << std::endl;
    int test = encodePNG(out_vec, w_blurry, h_blurry, argv[4]);

    return ret;
}