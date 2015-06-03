#!/bin/sh
gulp build
tar czf dist.tar.gz dist
scp dist.tar.gz ted2srt:/tmp/
ssh ted2srt /bin/bash <<'ENDSSH'
cd /tmp
tar xf dist.tar.gz
rsync -a --delete dist/ /var/www/ted2srt/app
ENDSSH
rm dist.tar.gz