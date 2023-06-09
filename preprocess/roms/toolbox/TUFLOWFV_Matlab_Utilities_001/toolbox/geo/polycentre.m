function C = polycentre(x,y)
siz = size(x);
if min(siz)~=1, error('ERROR:polycentre:notvector', 'input must be a vector'), end
if size(y)~=siz, error('ERROR:polycentre:xy', 'x and y input must be same size'), end
N = max(siz);
x0 = min(x);
y0 = min(y);
x = x - x0;
y = y - y0;
A = 0.5*(sum(x.*y([2:N 1])-x([2:N 1]).*y));
C = zeros(1,2);
C(1,1) = 1/6.0/A*sum((x+x([2:N 1])).*(x.*y([2:N 1])-x([2:N 1]).*y)) + x0;
C(1,2) = 1/6.0/A*sum((y+y([2:N 1])).*(x.*y([2:N 1])-x([2:N 1]).*y)) + y0;