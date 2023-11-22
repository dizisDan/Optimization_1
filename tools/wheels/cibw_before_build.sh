set -xe

PROJECT_DIR="$1"
PLATFORM=$(PYTHONPATH=tools python -c "import openblas_support; print(openblas_support.get_plat())")

# Update license
echo "" >> $PROJECT_DIR/LICENSE.txt
echo "----" >> $PROJECT_DIR/LICENSE.txt
echo "" >> $PROJECT_DIR/LICENSE.txt
cat $PROJECT_DIR/LICENSES_bundled.txt >> $PROJECT_DIR/LICENSE.txt
if [[ $RUNNER_OS == "Linux" ]] ; then
    cat $PROJECT_DIR/tools/wheels/LICENSE_linux.txt >> $PROJECT_DIR/LICENSE.txt
elif [[ $RUNNER_OS == "macOS" ]]; then
    cat $PROJECT_DIR/tools/wheels/LICENSE_osx.txt >> $PROJECT_DIR/LICENSE.txt
elif [[ $RUNNER_OS == "Windows" ]]; then
    cat $PROJECT_DIR/tools/wheels/LICENSE_win32.txt >> $PROJECT_DIR/LICENSE.txt
fi

install_openblas=true
if [[ $RUNNER_OS == "macOS" ]]; then
    if [[ $(sw_vers --productVersion) == 14.* ]]; then
        # This is the wheel build with Accelerate
        export MACOSX_DEPLOYMENT_TARGET=14.0
        install_openblas=false
    else
        # Done in gfortran_utils.sh
        echo "deployment target determined from Python interpreter"
    fi
fi

# Install Openblas
if [[ $RUNNER_OS == "Linux" || ($RUNNER_OS == "macOS" && $install_openblas) ]] ; then
    basedir=$(python tools/openblas_support.py --use-ilp64)
    if [[ $RUNNER_OS == "macOS" && $PLATFORM == "macosx-arm64" ]]; then
        # /usr/local/lib doesn't exist on cirrus-ci runners
        sudo mkdir -p /usr/local/lib /usr/local/include /usr/local/lib/cmake/openblas
        sudo mkdir -p /opt/arm64-builds/lib /opt/arm64-builds/include
        sudo chown -R $USER /opt/arm64-builds
        cp -r $basedir/lib/* /opt/arm64-builds/lib
        cp $basedir/include/* /opt/arm64-builds/include
        sudo cp -r $basedir/lib/* /usr/local/lib
        sudo cp $basedir/include/* /usr/local/include
    else
        cp -r $basedir/lib/* /usr/local/lib
        cp $basedir/include/* /usr/local/include
    fi
elif [[ $RUNNER_OS == "Windows" ]]; then
    # delvewheel is the equivalent of delocate/auditwheel for windows.
    python -m pip install delvewheel

    if [[ $PLATFORM == 'win-32' ]]; then
        echo "No BLAS used for 32-bit wheels"
    else
        # Note: DLLs are copied from /c/opt/64/bin by delvewheel, see
        # tools/wheels/repair_windows.sh
        mkdir -p /c/opt/64/lib/pkgconfig
        target=$(python -c "import tools.openblas_support as obs; plat=obs.get_plat(); target=f'openblas_{plat}.zip'; obs.download_openblas(target, plat, libsuffix='64_');print(target)")
        unzip -o -d /c/opt/ $target
    fi
fi

if [[ $RUNNER_OS == "macOS" ]]; then
    # Install same version of gfortran as the openblas-libs builds
    if [[ $PLATFORM == "macosx-arm64" ]]; then
        PLAT="arm64"
    fi

    # Needed for OpenBLAS and gfortran
    export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

    source $PROJECT_DIR/tools/wheels/gfortran_utils.sh
    install_gfortran
    pip install "delocate==0.10.4"
fi
