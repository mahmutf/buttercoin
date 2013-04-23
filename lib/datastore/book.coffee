DQ = require ('deque')
redblack = require('redblack')
Order = require('./order')

joinQueues = (front, back, withCb) ->
  withCb ||= (x) -> x
  until back.isEmpty()
    front.push withCb(back.shift())

mkCloseOrder = (order) -> {
  status: 'success'
  kind: 'order_filled'
  order: order
}

mkPartialOrder = (original_order, filled, remaining) -> {
  status: 'success'
  kind: 'order_partially_filled'
  filled_order: filled
  residual_order: remaining
  original_order: original_order
}

# BookStore provides an abstract interface for managing price levels.
# It's primary goal is to make it easier to swap store implementations when
# testing different backend performances.
#
# Once a suitable backend is found, this class should be considered for removal
class BookStore
  constructor: ->
    @tree = redblack.tree()
    @size = 0

  add_to_price_level: (price, order) =>
    level = @tree.get(price)

    unless level
      dq = new DQ.Dequeue()

      level = {
        size: 0
        orders: dq
      }
      @insert(price, level)

    level.orders.push(order)
    level.size += order.offered_amount


  # TODO - optimize this to allow for halting
  for_levels_above: (price, cb) =>
    cursor = @tree.range(0, price)
    running = true
    cursor.forEach (order_level, cur_price) =>
      running = cb(cur_price, order_level) if running

  insert: (price, level) =>
    @tree.insert(price, level)
    @size += 1

  delete: (price) =>
    @tree.delete(price)
    @size -= 1

  is_empty: => @size is 0

  forEach: (cb) => @tree.forEach(cb)


module.exports = class Book
  constructor: ->
    @store = new BookStore()

  fill_orders_with: (order) =>
    orig_order = order
    order = order.clone()
    #order.price = 1/order.price

    #cur = @store.head()
    closed = []
    amount_filled = 0
    amount_remaining = order.received_amount
    amount_spent = 0
    results = new DQ.Dequeue()

    @store.for_levels_above order.price, (price, order_level) =>
      # close the whole price level if we can
      if order_level.size <= amount_remaining
        amount_filled += order_level.size
        amount_remaining -= order_level.size
        amount_spent += order_level.size * price

        # queue the entire price level to be closed
        closed.push({price: price, order_level: order_level})
        return true # want more price levels
      else
        # consume all orders we can at this price level, starting with the oldest
        cur_order = order_level.orders.shift()
        while cur_order?.offered_amount <= amount_remaining
          amount_filled += cur_order.offered_amount
          amount_remaining -= cur_order.offered_amount
          amount_spent += cur_order.offered_amount * price

          order_level.size -= cur_order.offered_amount
          results.push mkCloseOrder(cur_order)
          
          # there must always be another order here or else we would have consumed
          # the entire price level at once
          #
          # if there isn't we have a major problem
          cur_order = order_level.orders.shift()
        
        if amount_remaining == 0
          # if we're done, put the cur_order back into the price level
          order_level.orders.unshift(cur_order)
        else if cur_order?.offered_amount > 0
          # diminish next order by remaining amount
          [filled, remaining] = cur_order.split(amount_remaining)
          order_level.size -= amount_remaining
          amount_filled += amount_remaining
          amount_spent += amount_remaining * price
          amount_remaining = 0

          # push the partially filled order back to the front of the queue
          order_level.orders.unshift(remaining)

          # report the partially filled order
          results.push mkPartialOrder(cur_order, filled, remaining)
        return false # don't want more price levels

    closed.forEach (x) =>
      joinQueues(results, x.order_level.orders, mkCloseOrder)
      @store.delete(x.price)

    order.offered_amount = amount_spent
    order.price = order.offered_amount / order.received_amount
    if amount_remaining == 0
      results.push mkCloseOrder(order)
    else if amount_filled == 0
      results.push {
        status: 'success'
        kind:   'not_filled'
        residual_order: orig_order
      }
    else
      # TODO - move to Order?
      filled = new Order(order.account,
                        order.offered_currency,
                        amount_spent,
                        order.received_currency,
                        amount_filled)
      remaining = new Order(order.account,
                            order.offered_currency,
                            (1/orig_order.price) * amount_remaining,
                            order.received_currency,
                            orig_order.received_amount - amount_filled)
      results.push mkPartialOrder(orig_order, filled, remaining)

    return results
  
  add_order: (order) =>
    @store.add_to_price_level(order.price, order)

    return {
      status: 'success'
      kind: 'order_opened'
      order: order
    }
