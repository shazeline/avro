mkdir -p build
VERSION=`cat share/VERSION.txt`
SRC_DIR=avro-src-$VERSION
DOC_DIR=avro-doc-$VERSION
mkdir -p build/$SRC_DIR
git archive trunk | tar -x -C build/$SRC_DIR
mvn -N -P rat antrun:run
mkdir -p dist
(cd build; tar czf ../dist/$SRC_DIR.tar.gz $SRC_DIR)
(cd lang/py; ant dist)
