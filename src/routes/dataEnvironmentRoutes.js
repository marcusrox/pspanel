const express = require('express');
const DataEnvironmentController = require('../controllers/dataEnvironmentController');

const router = express.Router();

router.get('/', DataEnvironmentController.show);

module.exports = router;
