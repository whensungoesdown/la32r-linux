#!/bin/bash

export CROSS_COMPILE=/home/u/loongson-gnu-toolchain-8.3-x86_64-loongarch32r-linux-gnusf-v2.0/bin/loongarch32r-linux-gnusf-
export ARCH=loongarch
export KCFLAGS="-mabi=ilp32s -march=loongarch32r"
export KAFLAGS="-mabi=ilp32s -march=loongarch32r"
OUT=la_build

if [ ! -d la_build ] ;then
    mkdir la_build
    make la32_soc2_mmu_defconfig O=${OUT}
fi

echo "----------------output ${OUT}----------------"

make menuconfig O=${OUT}
make vmlinux -j`nproc` O=${OUT} 2>&1 | tee -a build_error.log
