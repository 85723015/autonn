
# AutoNN #
AutoNN builds on [MatConvNet](http://www.vlfeat.org/matconvnet/)'s low-level functions and Matlab's math operators, to create a modern deep learning API with native automatic differentiation. The guiding principles are:

- Concise syntax for fast research prototyping, mixing math and deep network blocks freely.
- No boilerplate code to create custom layers, implemented as Matlab functions operating on GPU arrays.
- Minimal execution kernel for back-propagation, with a focus on speed.

Compared to the previous [wrappers](http://www.vlfeat.org/matconvnet/wrappers/) for MatConvNet, AutoNN is less verbose and has lower computational overhead.


# Requirements #

* A recent Matlab (preferably 2015b onwards, though older versions may also work).
* MatConvNet [version 24](http://www.vlfeat.org/matconvnet/) or [more recent](https://github.com/vlfeat/matconvnet).


# Getting started #

Extract the AutoNN files somewhere, then pull up a Matlab console and get confortable! The first step is to add MatConvNet to the path (with `vl_setupnn`), as well as AutoNN (with `setup_autonn`).

## Defining networks ##

A deep neural network is a particular case of a computational graph. With AutoNN, this graph is created by composing overloaded operators of special objects, much like in other modern frameworks that shall not be named. We start by defining one of the network's inputs:

```Matlab
images = Input()
```

We can then define the first operation, a convolution with a given kernel shape, which in MatConvNet is computed by the `vl_nnconv` function:

```Matlab
conv1 = vl_nnconv(images, 'size', [5, 5, 1, 20])
```

The resulting object has class `Layer`. The `Input` that we created earlier also subclasses `Layer`. All the MatConvNet functions are overloaded by the `Layer` class, so that instead of running them immediately, they instead produce a new `Layer` object. It is this nested structure of `Layer` objects that defines the network's topology.

According to the deep learning mantra, what this network needs is *more layers*. For demonstration purposes, we'll add just one pooling layer and another convolution:

```Matlab
pool1 = vl_nnpool(conv1, 2, 'stride', 2);
conv2 = vl_nnconv(pool1, 'size', [5, 5, 20, 10]);
```

The `vl_nnconv` syntax we used creates parameters for filters and biases automatically, initialized with the [Xavier](http://www.jmlr.org/proceedings/papers/v9/glorot10a/glorot10a.pdf) method (see `help Layer.vl_nnconv` for other initialization options).

We could, of course, also create these parameters explicitly. They are objects of class `Param` (again, a subclass of `Layer`), and on creation we specify their initial value:

```Matlab
filters = Param('value', 0.01 * randn(5, 5, 1, 20, 'single'));
biases = Param('value', zeros(20, 1, 'single'));
```

Our `conv1` layer could then, alternatively, be defined as:

```Matlab
conv1_alt = vl_nnconv(images, filters, biases);
```

This follows the function signature for MatConvNet's `vl_nnconv` function exactly (which can be checked with `help vl_nnconv`). The difference is that, instead of calling `vl_nnconv` immediately, the function call's signature is stored in a new `Layer` object, for later evaluation.

Note also that the filters and biases for `vl_nnconv` don't have to be of class `Param`. They could be any other `Layer` (i.e., the output of a subnetwork), or simple Matlab arrays (and thus constant).

There is generally no restriction in what options and arguments you use, since the list of arguments is stored as-is. This property extends to other functions, and to any custom layers that you may define. A layer type (both standard and custom) is just a function handle that accepts arbitrary arguments. To execute it in backward mode, computing a derivative, AutoNN will simply pass it an *extra* derivative argument, which can be easily detected by the function to act accordingly.


## Math functions ##

The `Layer` class overloads many math operators and native Matlab functions. Their derivatives are defined, so that it is possible to back-propagate derivatives through complex formulas.

Let's say one of your colleagues suggested that you test your network with [weight normalization](https://arxiv.org/abs/1602.07868). Scanning the paper, you see that it consists of normalizing the filters to unit norm, and then multiplying by a learned scalar parameter `g`, before feeding them to the convolution (eq. 2).

Normally you'd need to worry about computing the derivatives and creating some variant of the convolution layer. However, using the overloaded math operators in AutoNN, you can simply write down the formula:

```Matlab
filters = Param('value', randn(5, 5, 1, 20, 'single'));
g = Param('value', 1);
filters_wn = filters ./ sum(filters(:).^2) * g;
```

These filters can then be used in a convolutional layer:


```Matlab
conv1_wn = vl_nnconv(images, filters_wn, biases);
```

During network evaluation, the derivatives will be back-propagated correctly through the math operators and into the learnable parameters.

The full list of overloads can be seen with `methods('Layer')`. Some examples are array slicing and concatenation, element-wise algebra, reduction operations such as max or sum, and matrix algebra, including solving linear systems.


## Network evaluation ##

To run as efficiently as possible, the computational graph must be compiled into a simple sequence of instructions. This is stored as an object of class `Net`.

First, we will finish the network by adding a softmax loss:

```Matlab
labels = Input();
loss = vl_nnloss(conv2, labels);
```

Before compilation, we would like to assign nice names to the layers we defined - preferably the same names as the variables we used. This can be done automatically:

```Matlab
Layer.workspaceNames();
```

Only previously unnamed layers will be set. Similarly, `loss.sequentialNames()` would fill in unnamed layers involved in the computation of `loss`, using intuitive names like `convN` for the N'th convolutional layer, and `convN_filters` for the corresponding filters. To ensure all layers have names, network compilation will call this function. A layer's `name` property can also be set explicitly.

Finally, we compile the network by passing the loss to the `Net` constructor:

```Matlab
net = Net(loss);
```

This is now ready to run! Use the `eval` method to process some inputs, performing back-propagation:

```Matlab
net.eval({'images', rand(28, 28), 'labels', 1});
```

The derivative of the loss with respect to a variable (a layer's output) can then be accessed with `getDer`:

```Matlab
net.getDer('relu1')
```

The access methods for network variables are `getValue`/`setValue`, and for their derivatives `getDer`/`setDer`.

For serious training tasks, we should use the highly optimized GPU routines of MatConvNet and Matlab's `gpuArray`. We first need to select a GPU (e.g. GPU #1) with `gpuDevice(1)`. We can then mark the `images` input to be automatically transferred to the GPU, as follows:

```Matlab
images.gpu = true;
```

Note that this has to be done *before* compiling the network. The `gpu` property of `Param` objects is true by default. To actually enable the GPU computations, use:

```Matlab
net.move('gpu');
```

Using these elements, we can compose an SGD training loop. Simple examples of such loops are included in the directory `examples/minimal`. For more demanding tasks, it's probably best to use the `cnn_train_autonn` function, which supports different solvers (such as AdaGrad, RMSProp, AdaDelta, ADAM), multi-GPU training, checkpointing, and more.



# Documentation #

Comprehensive documentation is available by typing `help autonn` into the Matlab console. This lists all the classes and methods, with short descriptions, and provides links to other documentation pages.


# Examples #

The easiest way to learn more is probably to look inside the `examples` directory, which has heavily-commented samples. These can be grouped in two categories:

- The *minimal* examples (in `examples/minimal`) are very short and self-contained. They are scripts so you can inspect and explore the resulting variables in the command window. The SGD optimization is a simple `for` loop, so if you prefer to have full control over learning this is the way to go.

- The *full* examples (in `examples/cnn` and `examples/rnn`) demonstrate training using `cnn_train_autonn`, equivalent to the MatConvNet `cnn_train` function. This includes the standard options, such as checkpointing and different solvers.

The ImageNet and MNIST examples work exactly the same as the corresponding MatConvNet examples, except for the network definitions. There is also a text LSTM example (`examples/rnn/rnn_lstm_shakespeare.m`), and a CNN on toy data (`examples/cnn/cnn_toy_data_autonn.m`), which provides a good starting point for training on custom datasets.

