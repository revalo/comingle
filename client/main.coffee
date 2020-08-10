import React from 'react'
import {Meteor} from 'meteor/meteor'
import {render} from 'react-dom'

import App from './App'
import '/lib/main.coffee'
import './FlexLayout.scss'

Meteor.startup ->
  render <App/>, document.getElementById 'react-root'