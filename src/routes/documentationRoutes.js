const express = require('express');
const DocumentationController = require('../controllers/documentationController');

const router = express.Router();

router.get('/', DocumentationController.show);
router.get('/view/:documentId', DocumentationController.view);

module.exports = router;
