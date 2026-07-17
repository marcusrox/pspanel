const express = require('express');
const RuntimeEnvironmentController = require('../controllers/runtimeEnvironmentController');

const router = express.Router();

router.get('/', RuntimeEnvironmentController.show);

module.exports = router;
