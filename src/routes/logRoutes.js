const express = require('express');
const LogController = require('../controllers/logController');

const router = express.Router();

router.get('/', LogController.showLogs);
router.get('/content', LogController.getLogContent);

module.exports = router;
