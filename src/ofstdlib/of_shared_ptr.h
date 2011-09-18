/*
 * File: of_shared_ptr.h
 *
 * About: Version
 *  This is version 1 of the file.
 *
 * About: Purpose
 *  shared_ptr class header.
 *
 * About: Author
 *  Daniel "q66" Kolesa <quaker66@gmail.com>
 *
 *  Originally inspired by implementation from ecaprice library
 *  (http://github.com/graphitemaster/ecaprice) by Dale "graphitemaster"
 *  Weiler, currently completely custom implementation.
 *
 * About: License
 *  This file is licensed under MIT. See COPYING.txt for more information.
 */

#ifndef OF_SHARED_PTR_H
#define OF_SHARED_PTR_H

#include <cstdlib>

#include "of_utils.h"

/*
 * Package: types
 * This namespace features some types used in OctaForge.
 * This part exactly defines shared_ptr.
 */
namespace types
{
    /*
     * Class: shared_ptr
     * A shared pointer. Basically a reference counted container.
     * Useful for i.e. storing pointers in various container types
     * like vectors and hashtables without risking leaks.
     */
    template<typename T> struct shared_ptr
    {
        /*
         * Constructor: shared_ptr
         * Initializes empty shared_ptr.
         */
        shared_ptr(): ptr(NULL), count(NULL)
        {
            count = new counter;
        }

        /*
         * Constructor: shared_ptr
         * Initializes shared_ptr from shared_ptr.
         * Increments the counter.
         */
        shared_ptr(const shared_ptr<T>& p): ptr(p.ptr), count(p.count)
        {
            count->increment();
        }

        /*
         * Constructor: shared_ptr
         * Initializes shared_ptr from a pointer.
         */
        shared_ptr(T *p): ptr(p), count(NULL)
        {
            count = new counter;
        }

        /*
         * Destructor: shared_ptr
         * Decrements the <counter>. If it reaches 0,
         * both pointer and counter will be freed.
         */
        ~shared_ptr()
        {
            if (count && count->decrement() == 0)
            {
                delete ptr;
                delete count;
            }
        }

        /*
         * Operator: =
         * Assigns the shared_ptr from another one. Inherits
         * its reference count and increments it by one.
         */
        shared_ptr<T>& operator=(const shared_ptr<T>& p)
        {
            if (p != *this)
            {
                if (count && count->decrement() == 0)
                {
                    delete ptr;
                    delete count;
                }
                ptr   = p.ptr;
                count = p.count;
                count->increment();
            }
            return *this;
        }

        /*
         * Operator: ->
         * Overload of this operator so you can manipulate
         * with the container simillarily to standard pointer.
         */
        T *operator->() { return ptr; }

        /*
         * Operator: *
         * Overload of this operator so you can manipulate
         * with the container simillarily to standard pointer.
         */
        T& operator*() { return *ptr; }

        /*
         * Operator: ->
         * Overload of this operator so you can manipulate
         * with the container simillarily to standard pointer.
         * Const version.
         */
        const T *operator->() const { return ptr; }

        /*
         * Operator: *
         * Overload of this operator so you can manipulate
         * with the container simillarily to standard pointer.
         * Const version.
         */
        const T& operator*() const { return *ptr; }

        /*
         * Operator: ==,!=,<,<=,>,>=
         * Overloads for comparison operators.
         */
        bool operator==(const shared_ptr<T>& p) const { return ptr == p.ptr; }
        bool operator!=(const shared_ptr<T>& p) const { return ptr != p.ptr; }
        bool operator< (const shared_ptr<T>& p) const { return ptr <  p.ptr; }
        bool operator<=(const shared_ptr<T>& p) const { return ptr <= p.ptr; }
        bool operator> (const shared_ptr<T>& p) const { return ptr >  p.ptr; }
        bool operator>=(const shared_ptr<T>& p) const { return ptr >= p.ptr; }

        /*
         * Variable: counter
         * A simple nested struct holding the count.
         * It has two methods, increment, which returns
         * nothing, and decrement, which returns --count.
         */
        struct counter
        {
            counter(): count(1) {};

            void   increment() {        count++; }
            size_t decrement() { return --count; }

            size_t count;
        };

        /*
         * Variable: ptr
         * The pointer.
         */
        T *ptr;

        /*
         * Variable: count
         * Current instance of <counter>.
         */
        counter *count;
    };
} /* end namespace types */

#endif
