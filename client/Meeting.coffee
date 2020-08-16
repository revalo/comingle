import React, {useState, useEffect, useReducer} from 'react'
import {Switch, Route, useParams, useLocation, useHistory} from 'react-router-dom'
import FlexLayout from './FlexLayout'
import {Tooltip, OverlayTrigger} from 'react-bootstrap'
import {Session} from 'meteor/session'
import {useTracker} from 'meteor/react-meteor-data'
import {FontAwesomeIcon} from '@fortawesome/react-fontawesome'
import {faDoorOpen, faEye, faEyeSlash} from '@fortawesome/free-solid-svg-icons'

import {RoomList} from './RoomList'
import {Room} from './Room'
import {Rooms} from '/lib/rooms'
import {Presence} from '/lib/presence'
import {validId} from '/lib/id'
import {getPresenceId, getCreator} from './lib/presenceId'
import {useIdMap} from './lib/useIdMap'
import {formatDate} from './lib/dates'

initModel = ->
  model = FlexLayout.Model.fromJson
    global:
      borderEnableDrop: false
    borders: [
      type: 'border'
      location: 'left'
      selected: 0
      children: [
        id: 'roomsTab'
        type: 'tab'
        name: "Meeting Rooms"
        component: 'RoomList'
        enableClose: false
        enableDrag: false
      ]
    ]
    layout:
      id: 'root'
      type: 'row'
      weight: 100
      children: []
  model.setOnAllowDrop (dragNode, dropInfo) ->
    return false if dropInfo.node.getId() == 'roomsTabSet' and dropInfo.location != FlexLayout.DockLocation.RIGHT
    #return false if dropInfo.node.getType() == 'border'
    #return false if dragNode.getParent()?.getType() == 'border'
    true
  model

export Meeting = ->
  {meetingId} = useParams()
  [model, setModel] = useState initModel
  location = useLocation()
  history = useHistory()
  {loading, rooms} = useTracker ->
    sub = Meteor.subscribe 'meeting', meetingId
    loading: not sub.ready()
    rooms: Rooms.find().fetch()
  id2room = useIdMap rooms
  useEffect ->
    for room in rooms
      if model.getNodeById room._id
        model.doAction FlexLayout.Actions.updateNodeAttributes room._id,
          name: room.title
    undefined
  , [rooms]
  useEffect ->
    if location.hash and validId id = location.hash[1..]
      unless model.getNodeById id
        tab =
          id: id
          type: 'tab'
          name: Rooms.findOne(id)?.title ? id
          component: 'Room'
          config: showDeleted: false
        tabset = FlexLayout.getActiveTabset model
        model.doAction FlexLayout.Actions.addNode tab,
          tabset.getId(), FlexLayout.DockLocation.CENTER, -1
      FlexLayout.forceSelectTab model, id
    undefined
  , [location.hash]
  [showDeleted, setShowDeleted] = useReducer(
    (state, {id, value}) ->
      model.doAction FlexLayout.Actions.updateNodeAttributes id,
        config: showDeleted: value
      state[id] = value
      state
  , {})
  presenceId = getPresenceId()
  name = useTracker -> Session.get 'name'
  updatePresence = ->
    return unless name?  # wait for tracker to load name
    presence =
      id: presenceId
      meeting: meetingId
      name: name
      rooms:
        visible: []
        invisible: []
    model.visitNodes (node) ->
      if node.getType() == 'tab' and node.getId() != 'roomsTab'
        if node.isVisible()
          presence.rooms.visible.push node.getId()
        else
          presence.rooms.invisible.push node.getId()
    current = Presence.findOne
      id: presenceId
      meeting: meetingId
    unless current? and current.name == presence.name and
           current?.rooms?.visible?.toString?() ==
           presence.rooms.visible.toString() and
           current?.rooms?.invisible?.toString?() ==
           presence.rooms.invisible.toString()
      Meteor.call 'presenceUpdate', presence
  ## Send presence when name changes or when we reconnect to server
  ## (so server may have deleted our presence information).
  useEffect updatePresence, [name]
  useTracker -> updatePresence() if Meteor.status().connected
  onAction = (action) ->
    switch action.type
      when FlexLayout.Actions.RENAME_TAB
        ## Sanitize room title and push to other users
        action.data.text = action.data.text.trim()
        return unless action.data.text  # prevent empty title
        Meteor.call 'roomEdit',
          id: action.data.node
          title: action.data.text
          updator: getCreator()
    action
  onModelChange = ->
    updatePresence()
    ## Maintain hash part of URL to point to "current" tab.
    tabset = FlexLayout.getActiveTabset model
    if tabset and tab = tabset.getSelectedNode()
      unless location.hash == "##{tab.getId()}"
        history.replace "/m/#{meetingId}##{tab.getId()}"
    else
      if location.hash
        history.replace "/m/#{meetingId}"
  factory = (node) ->
    switch node.getComponent()
      when 'RoomList' then <RoomList loading={loading}/>
      when 'Room'
        if node.isVisible()
          <Room loading={loading} roomId={node.getId()} {...node.getConfig()}/>
        else
          null  # don't render hidden rooms, in particular to cancel all calls
  tooltip = (node) -> (props) ->
    room = id2room[node.getId()]
    return <span/> unless room
    <Tooltip {...props}>
      Room &ldquo;{room.title}&rdquo;<br/>
      created by {room.creator?.name ? 'unknown'}<br/>
      on {formatDate room.created}
    </Tooltip>
  iconFactory = (node) ->
    <OverlayTrigger placement="bottom" overlay={tooltip node}>
      <FontAwesomeIcon icon={faDoorOpen}/>
    </OverlayTrigger>
  onRenderTab = (node, renderState) ->
    return if node.getComponent() == 'RoomList'
    renderState.content =
      <OverlayTrigger placement="bottom" overlay={tooltip node}>
        <span className="tab-title">{renderState.content}</span>
      </OverlayTrigger>
    if node.isVisible()  # special buttons for visible tabs
      id = node.getId()
      buttons = renderState.buttons
      type = if node.getParent().getType() == 'border' then 'border' else 'tab'
      showDeleted = node.getConfig()?.showDeleted
      label =
        if showDeleted
          "Hide Deleted Tabs"
        else
          "Show Deleted Tabs"
      buttons?.push \
        <div key="deleted"
         className="flexlayout__#{type}_button_trailing"
         aria-label={label}
         onClick={-> setShowDeleted {id, value: not showDeleted}}
         onMouseDown={(e) -> e.stopPropagation()}
         onTouchStart={(e) -> e.stopPropagation()}>
          <OverlayTrigger placement="bottom" overlay={(props) ->
            <Tooltip {...props}>
              {label}<br/>
              <small>Currently {unless showDeleted then <b>not</b>} showing deleted tabs.</small>
            </Tooltip>
          }>
            <FontAwesomeIcon icon={if showDeleted then faEye else faEyeSlash}/>
          </OverlayTrigger>
        </div>
  <FlexLayout.Layout model={model} factory={factory} iconFactory={iconFactory}
   onRenderTab={onRenderTab}
   onAction={onAction} onModelChange={-> setTimeout onModelChange, 0}
   tabPhrase="room"/>
