rm -r dist/; QUILL_CMS=https://cms.quill.org NODE_ENV=production EMPIRICAL_BASE_URL=https://www.quill.org PUSHER_KEY=b2cbf247b2e2d930b21d FIREBASE_APP_NAME=quillconnect webpack --optimize-minimize
firebase deploy --project production
aws s3 sync ./dist/ s3://aws-website-quillconnect-6sy4b
./rollbar.sh
