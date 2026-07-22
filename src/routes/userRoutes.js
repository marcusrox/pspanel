const express = require('express');
const userController = require('../controllers/userController');

const router = express.Router();

router.get('/audit', userController.audit);
router.get('/:id', userController.detail);
router.get('/', userController.list);

module.exports = router;
