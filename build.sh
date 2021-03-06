#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e						  # exit on error

cd `dirname "$0"`				  # connect to root

VERSION=`cat share/VERSION.txt`

function usage {
  echo "Usage: $0 {test|dist|sign|clean|docker|rat}"
  exit 1
}

if [ $# -eq 0 ]
then
  usage
fi

set -x						  # echo commands

for target in "$@"
do

case "$target" in

    test)
	# run lang-specific tests
        (cd lang/java; mvn3 test)
	(cd lang/py; ant test)

	# create interop test data
        mkdir -p build/interop/data
	(cd lang/java/avro; mvn3 -P interop-data-generate generate-resources)
	(cd lang/py; ant interop-data-generate)

	# run interop data tests
	(cd lang/java; mvn3 test -P interop-data-test)
	(cd lang/py; ant interop-data-test)

	# java needs to package the jars for the interop rpc tests
        (cd lang/java; mvn3 package -DskipTests)
	# run interop rpc test
        /bin/bash share/test/interop/bin/test_rpc_interop.sh

	;;

    dist)
        # ensure version matches
        # FIXME: enforcer is broken:MENFORCER-42
        # mvn3 enforcer:enforce -Davro.version=$VERSION
        
	# build source tarball
        mkdir -p build

        SRC_DIR=avro-src-$VERSION
        DOC_DIR=avro-doc-$VERSION

	rm -rf build/${SRC_DIR}
	svn export --force . build/${SRC_DIR}

	#runs RAT on artifacts
        mvn3 -N -P rat antrun:run

	mkdir -p dist
        (cd build; tar czf ../dist/${SRC_DIR}.tar.gz ${SRC_DIR})

	# build lang-specific artifacts
        
	(cd lang/java; mvn3 package -DskipTests -Dhadoop.version=1;
	  rm -rf mapred/target/{classes,test-classes}/;
	  rm -rf trevni/avro/target/{classes,test-classes}/;
	  mvn3 -P dist package -DskipTests -Davro.version=$VERSION javadoc:aggregate)
        (cd lang/java/trevni/doc; mvn3 site)
        (mvn3 -N -P copy-artifacts antrun:run) 

	(cd lang/py; ant dist)

	# build docs
	(cd doc; ant)
        # add LICENSE and NOTICE for docs
        mkdir -p build/$DOC_DIR
        cp doc/LICENSE build/$DOC_DIR
        cp doc/NOTICE build/$DOC_DIR
	(cd build; tar czf ../dist/avro-doc-$VERSION.tar.gz $DOC_DIR)

	cp DIST_README.txt dist/README.txt
	;;

    sign)

	set +x

	echo -n "Enter password: "
	stty -echo
	read password
	stty echo

	for f in $(find dist -type f \
	    \! -name '*.md5' \! -name '*.sha1' \
	    \! -name '*.asc' \! -name '*.txt' );
	do
	    (cd `dirname $f`; md5sum `basename $f`) > $f.md5
	    (cd `dirname $f`; sha1sum `basename $f`) > $f.sha1
	    gpg --passphrase $password --armor --output $f.asc --detach-sig $f
	done

	set -x
	;;

    clean)
	rm -rf build dist
	(cd doc; ant clean)

        (mvn3 clean)         

	(cd lang/py; ant clean)
	;;

    docker)
        docker build -t avro-build share/docker
        if [ "$(uname -s)" == "Linux" ]; then
          USER_NAME=${SUDO_USER:=$USER}
          USER_ID=$(id -u $USER_NAME)
          GROUP_ID=$(id -g $USER_NAME)
        else # boot2docker uid and gid
          USER_NAME=$USER
          USER_ID=1000
          GROUP_ID=50
        fi
        docker build -t avro-build-${USER_NAME} - <<UserSpecificDocker
FROM avro-build
RUN groupadd -g ${GROUP_ID} ${USER_NAME} || true
RUN useradd -g ${GROUP_ID} -u ${USER_ID} -k /root -m ${USER_NAME}
ENV HOME /home/${USER_NAME}
UserSpecificDocker
        # By mapping the .m2 directory you can do an mvn install from
        # within the container and use the result on your normal
        # system.  And this also is a significant speedup in subsequent
        # builds because the dependencies are downloaded only once.
        docker run --rm=true -t -i \
          -v ${PWD}:/home/${USER_NAME}/avro \
          -w /home/${USER_NAME}/avro \
          -v ${HOME}/.m2:/home/${USER_NAME}/.m2 \
          -v ${HOME}/.gnupg:/home/${USER_NAME}/.gnupg \
          -u ${USER_NAME} \
          avro-build-${USER_NAME}
        ;;

    rat)
        mvn3 test -Dmaven.main.skip=true -Dmaven.test.skip=true -DskipTests=true -P rat -pl :avro-toplevel
        ;;

    *)
        usage
        ;;
esac

done

exit 0
