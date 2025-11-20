#!/bin/bash

# Create a dummy settings.js file mimicking the user's file
cat <<EOF > test_settings.js
module.exports = {
    // Some comments
    flowFile: "default.json",
    // More settings
}
EOF

echo "Testing current regex (GNU extension \s)..."
# This is the current command in run.sh
sed "s|module.exports\s*=\s*{|MATCHED|" test_settings.js > result_gnu.js

if grep -q "MATCHED" result_gnu.js; then
    echo "✅ Current regex works in this environment."
else
    echo "❌ Current regex FAILED. This confirms \s is not supported."
fi

echo ""
echo "Testing proposed regex (POSIX [[:space:]])..."
# This is the proposed fix
sed "s|module.exports[[:space:]]*=[[:space:]]*{|MATCHED|" test_settings.js > result_posix.js

if grep -q "MATCHED" result_posix.js; then
    echo "✅ Proposed regex works."
else
    echo "❌ Proposed regex FAILED."
fi

rm test_settings.js result_gnu.js result_posix.js
