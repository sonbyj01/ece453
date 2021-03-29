/*
* Henry Son
* ECE453 - Advanced Computer Architecture
* Professor Billoo
* 
* CPU deblurring
*
* Reference(s):
* http://www.geom.uiuc.edu/~huberty/math5337/groupe/digits.html
*/

#include "../../dep/metrics/metrics.h"
#include "../../dep/lodepng/lodepng.h"

#include <iostream>
#include <algorithm>
#include <chrono>

#include <math.h>

const double PI = 3.14159265358979323846;

double _divide(double a, double b) {
    if(b == 0) {
        return a;
    }
    return a / b;
}

std::vector<std::vector<std::vector<double>>> calculatePSF(std::vector<std::vector<std::vector<double>>> &psf_hat) {
    int psf_size = 5;
    double mean_row = 0.0;
    double mean_col = 0.0;
    double sigma_row = 49;
    double sigma_col = 36;
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
			psf_final[row][col][0] = curr/3;
			psf_final[row][col][1] = curr/3;
			psf_final[row][col][2] = curr/3;
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
    
	return psf_final;
}

std::vector<double> decodePNG(const char* filename, unsigned &w, unsigned &h) {
    std::vector<unsigned char> image;
    unsigned error = lodepng::decode(image, w, h, filename);

    if(error) {
        std::cerr << "ERROR: " << error << "Unable to decode PNG file, " << filename << std::endl;
        exit(-1);
    }

    std::vector<int> image_without_alpha;

    for(unsigned int i = 0; i < image.size(); i++) {
        if(i % 4 != 3) {
            image_without_alpha.push_back((int)image[i]);
        }
    }

    std::vector<double> doubleVector(image_without_alpha.begin(), image_without_alpha.end());
    return doubleVector;
}

void convert1D(std::vector<std::vector<std::vector<double>>> &a, std::vector<unsigned char> &vec1D) {
    for(unsigned i = 0; i < a.size(); i++) {
        for(unsigned j = 0; j < a[0].size(); j++) {
            vec1D.push_back(round(a[i][j][0]));
            vec1D.push_back(round(a[i][j][1]));
            vec1D.push_back(round(a[i][j][2]));
            vec1D.push_back((unsigned char)(255));
        }
    }
}

std::vector<std::vector<double>> convert2D(std::vector<double> &vec1D, unsigned w, unsigned h) {
    std::vector<std::vector<double>> vec2D;
    vec2D.resize(h);

    for(unsigned i = 0; i < h; i++) {
        vec2D[i].resize(w);
    }

    for(unsigned i = 0; i < vec1D.size(); i++) {
        int row = i / w;
        int col = i % w;

        vec2D[row][col] = vec1D[i];
    }

    return vec2D;
}

void elementWiseMul(std::vector<std::vector<std::vector<double>>> &a, std::vector<std::vector<std::vector<double>>> &b, std::vector<std::vector<std::vector<double>>> &c) {
    if(a.size() != b.size() || a[0].size() != b[0].size() || a[0][0].size() != b[0][0].size()) {
        std::cerr << "Error in Element Wise Multiplication: Dimensions do not agree." << std::endl;
        std::cerr << "Dimension of A: [" << a.size() << ", " << a[0].size() << ", " << a[0][0].size() << "]" << std::endl;
        std::cerr << "Dimension of B: [" << b.size() << ", " << b[0].size() << ", " << b[0][0].size() << "]" << std::endl;
        exit(-1);
    }

    for(unsigned i = 0; i < a.size(); i++) {
        for(unsigned j = 0; j < a[0].size(); j++) {
            std::transform(a[i][j].begin(), 
                           a[i][j].end(), 
                           b[i][j].begin(), 
                           c[i][j].begin(), 
                           std::multiplies<double>());
        }
    }
}

void elementWiseDiv(std::vector<std::vector<std::vector<double>>> &a, std::vector<std::vector<std::vector<double>>> &b, std::vector<std::vector<std::vector<double>>> &c) {
    if(a.size() != b.size() || a[0].size() != b[0].size() || a[0][0].size() != b[0][0].size()) {
        std::cerr << "Error in Element Wise Division: Dimensions do not agree." << std::endl;
        std::cerr << "Dimension of A: [" << a.size() << ", " << a[0].size() << ", " << a[0][0].size() << "]" << std::endl;
        std::cerr << "Dimension of B: [" << b.size() << ", " << b[0].size() << ", " << b[0][0].size() << "]" << std::endl;
        exit(-1);
    }

    for(unsigned i = 0; i < a.size(); i++) {
        for(unsigned j = 0; j < a[0].size(); j++) {
            c[i][j][0] = _divide(a[i][j][0], b[i][j][0]);
            c[i][j][1] = _divide(a[i][j][1], b[i][j][1]);
            c[i][j][2] = _divide(a[i][j][2], b[i][j][2]);
        }
    }
}

std::vector<std::vector<std::vector<double>>> convolve(std::vector<std::vector<std::vector<double>>> &src, std::vector<std::vector<std::vector<double>>> &kernel) {
    std::vector<std::vector<std::vector<double>>> returnable(src.size(), std::vector<std::vector<double>> (src[0].size(), std::vector<double> (3, 0.0, 0

    int kernel_center_x = kernel[0].size() / 2;
    int kernel_center_y = kernel.size() / 2;
    int rows = src.size();
    int columns = src[0].size();

    for(int i = 0; i < rows; i++) {
        for(int j = 0; j < cols; j++) {
            for(unsigned a = 0; a < kernel.size(); m++) {
                for(unsigned b = 0; b < kernel[0].size(); n++) {
                    int temp1 = i + (m - kernel_center_y);
                    int temp2 = j + (n - kernel_center_x);

                    if(temp1 >= 0 && temp1 < rows && temp2 >= 0 && temp2 < cols) {
                        std::vector<double> temp(3, 0);

                        returnable[i][j][0] += src[temp1][temp2][0] * kernel[m][n][0];
                        returnable[i][j][1] += src[temp1][temp2][1] * kernel[m][n][1];
                        returnable[i][j][2] += src[temp1][temp2][2] * kernel[m][n][2];
                    }
                }
            }
        }
    }
    return returnable;
}

int main(int argc, char *argv[]) {
    if(argc < 5) {
        std::cerr << "Usage: " << argv[0] << " [BLURRY IMAGE PNG FILE] [ORIGINAL IMAGE PNG FILE] [iterations] [OUTPUT FILE]" << std::endl;
        exit(-1)
    }

    const char *blurryfile = argv[1];
    const char *origfile = argv[2];
    int iterations = atoi(argv[3]);
    const char *fileout = argv[4];

    unsigned blury_w, blurry_h, orig_w, orig_h;

    std::vector<double> img = decodePNG(blurryfile, blurry_w, blurry_h);
    std::vector<double> ref = decodePNG(origfile, orig_w, orig_h);

    std::vector<int> img_int(img.begin(), img.end());
    std::vector<int> ref_int(ref.begin(), ref.end());

    std::vector<std::vector<std::vector<double>>> final_rgb_img;
    final_rgb_img.resize(h_blurry);

    std::vector<std::vector<double>> initial = convert2D(img, blurry_w * 3, blurry_h);

    for(unsigned i = 0; i < initial.size(); i++) {
        final_rgb_img[i] = convert2D(initial[i], 3, blurry_w);
    }

    std::vector<std::vector<std::vector<double>>> psf_hat;
    std::vector<std::vector<std::vector<double>>> psf = calculatePSF(psf_hat);

    auto latent_est(final_rgb_img);
    std::vector<std::vector<std::vector<double>>> relative_blur(blurry_h, std::vector<std::vector<double>> (blurry_w, std::vector<double> (3, 0)));

    auto start = std::chrono::high_resolution_clock::now();
    for(int i = 0; i < iterations; i++) {
        std::vector<std::vector<std::vector<double>>> est_conv = convolve(latent_est, psf);
        elementWiseDiv(final_rgb_img, est_conv, relative_blur);

        auto temp(latent_est);
        std::vector<std::vector<std::vector<double>>> error_est = convolve(relative_blur, psf_hat);
        elementWiseMul(temp, error_est, latent_est);
    }
    auto stop std::chrono::high_resolution_clock::now();

    auto duration = std::chrono::duration_cast<std::chrono::milliseconds> (stop - start);
    std::cout << "Elapsed time (ms): " << duration.count() << std::endl;

    std::vector<unsigned char> est1D; 
    std::vector<int> est1D_without_alpha;
    
    convert1D(latent_est, est1D);

    lodepng::encode(fileout, est1D, blurry_w, blurry_h);

    for(unsigned i = 0; i < est1D.size(); i++) {
        if(i % 4 != 3) {
            est1D)without_alpha.push_back((int)est1D[i]);
        }
    }

    std::cout << "The blurry MSE is " << _mse(img_int, blurry_w, Blurry_h, ref_int) << std::endl;
    std::cout << "The blurry pSNR is " << psnr(img_int, blurry_w, Blurry_h, ref_int) << std::endl;
    std::cout << "The estimated MSE is " << _mse(est1D_without_alpha, blurry_w, Blurry_h, ref_int) << std::endl;
    std::cout << "The estimated pSNR is " << psnr(est1D_without_alpha, blurry_w, Blurry_h, ref_int) << std::endl;
    return 0;
}